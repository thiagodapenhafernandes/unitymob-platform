require "open3"
require "tmpdir"

module Whatsapp
  # Converte anexos que a Meta rejeita (ex.: .mov do iPhone) para um formato
  # aceito ANTES do upload. Estratégia: remux rápido (troca de container, sem
  # re-encode); se o resultado passar do limite da Meta, re-encoda comprimindo.
  # Re-anexa o resultado na própria mensagem — thread e Meta passam a usar MP4.
  module MediaConverter
    VIDEO_MAX_BYTES = MediaSupport::SUPPORTED_MEDIA.fetch("video").fetch(:max_bytes)
    AUDIO_MAX_BYTES = MediaSupport::SUPPORTED_MEDIA.fetch("audio").fetch(:max_bytes)

    module_function

    def ffmpeg_bin
      ENV.fetch("FFMPEG_BIN", "ffmpeg")
    end

    def available?
      return @available unless @available.nil?

      _out, _err, status = Open3.capture3(ffmpeg_bin, "-version")
      @available = status.success?
    rescue Errno::ENOENT
      @available = false
    end

    # Converte o anexo da mensagem se necessário. Retorna { ok: true } quando
    # não há nada a converter ou a conversão deu certo; { ok: false, error: }
    # quando o envio deve falhar com mensagem clara.
    def ensure_supported!(message)
      return { ok: true } unless message.media_file.attached?

      blob = message.media_file.blob
      content_type = MediaSupport.resolved_content_type(blob)

      # Safari (PWA iOS) grava audio/mp4 FRAGMENTADO, que a Meta rejeita no
      # upload — remuxa para m4a comum (faststart) antes de subir.
      if content_type == "audio/mp4"
        return { ok: true } unless available?

        return normalize_audio_mp4!(message, blob)
      end

      return { ok: true } unless MediaSupport.convertible_content_type?(content_type)

      unless available?
        return { ok: false, error: "Este formato precisa de conversão e o ffmpeg não está disponível no servidor." }
      end

      case content_type
      when "audio/webm" then convert_audio!(message, blob)
      else convert_video!(message, blob)
      end
    end

    def normalize_audio_mp4!(message, blob)
      basename = File.basename(blob.filename.to_s, ".*").presence || "audio"

      Dir.mktmpdir("wa-media") do |dir|
        input = File.join(dir, "input.m4a")
        File.open(input, "wb") { |file| blob.download { |chunk| file.write(chunk) } }

        # OGG/Opus: a Meta reprocessa m4a remuxado como octet-stream (erro 131053);
        # opus e o formato de nota de voz nativo do WhatsApp e passa sempre.
        output = File.join(dir, "#{basename}.ogg")
        encoded = run_ffmpeg(["-i", input, "-vn", "-c:a", "libopus", "-b:a", "32k", "-ac", "1", output])
        return { ok: true } unless encoded && File.exist?(output) # sem conversao: tenta como veio

        File.open(output, "rb") do |file|
          message.media_file.attach(io: file, filename: "#{basename}.ogg", content_type: "audio/ogg", identify: false)
        end
      end

      { ok: true, converted: true }
    end

    # Gravacao de voz do navegador (webm/opus) -> OGG/Opus, aceito pela Meta.
    def convert_audio!(message, blob)
      basename = File.basename(blob.filename.to_s, ".*").presence || "audio"

      Dir.mktmpdir("wa-media") do |dir|
        input = File.join(dir, "input.webm")
        File.open(input, "wb") { |file| blob.download { |chunk| file.write(chunk) } }

        output = File.join(dir, "#{basename}.ogg")

        # 1a tentativa: copia do stream opus (sem re-encode)
        copied = run_ffmpeg(["-i", input, "-vn", "-c:a", "copy", "-f", "ogg", output])
        unless copied && File.exist?(output) && File.size(output).positive?
          File.delete(output) if File.exist?(output)
          encoded = run_ffmpeg(["-i", input, "-vn", "-c:a", "libopus", "-b:a", "32k", "-ac", "1", output])
          unless encoded && File.exist?(output)
            return { ok: false, error: "Não foi possível converter o áudio gravado." }
          end
        end

        if File.size(output) > AUDIO_MAX_BYTES
          return { ok: false, error: "Áudio excede o limite da WhatsApp Cloud API (#{AUDIO_MAX_BYTES / 1.megabyte} MB)." }
        end

        File.open(output, "rb") do |file|
          message.media_file.attach(io: file, filename: "#{basename}.ogg", content_type: "audio/ogg", identify: false)
        end
      end

      { ok: true, converted: true }
    end

    def convert_video!(message, blob)
      basename = File.basename(blob.filename.to_s, ".*").presence || "video"

      Dir.mktmpdir("wa-media") do |dir|
        input = File.join(dir, "input#{File.extname(blob.filename.to_s).presence || '.mov'}")
        File.open(input, "wb") { |file| blob.download { |chunk| file.write(chunk) } }

        output = File.join(dir, "#{basename}.mp4")

        # 1ª tentativa: remux (cópia de streams — rápido, sem perda)
        remuxed = run_ffmpeg(["-i", input, "-c", "copy", "-movflags", "+faststart", output])
        if !remuxed || File.size(output).to_i > VIDEO_MAX_BYTES
          # 2ª tentativa: re-encode comprimido (720p, H.264/AAC)
          File.delete(output) if File.exist?(output)
          encoded = run_ffmpeg([
            "-i", input,
            "-vf", "scale='min(1280,iw)':-2",
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "28",
            "-c:a", "aac", "-b:a", "96k",
            "-movflags", "+faststart",
            output
          ])
          unless encoded && File.exist?(output)
            return { ok: false, error: "Não foi possível converter o vídeo para MP4." }
          end
        end

        if File.size(output) > VIDEO_MAX_BYTES
          max_mb = VIDEO_MAX_BYTES / 1.megabyte
          return { ok: false, error: "Vídeo excede o limite da WhatsApp Cloud API (#{max_mb} MB) mesmo após compressão. Envie um trecho menor." }
        end

        File.open(output, "rb") do |file|
          # substitui o anexo; o nome/tipo novos ficam no proprio attachment
          message.media_file.attach(io: file, filename: "#{basename}.mp4", content_type: "video/mp4")
        end
      end

      { ok: true, converted: true }
    end

    def run_ffmpeg(args)
      _out, _err, status = Open3.capture3(ffmpeg_bin, "-y", "-hide_banner", "-loglevel", "error", *args)
      status.success?
    rescue Errno::ENOENT
      false
    end
  end
end
