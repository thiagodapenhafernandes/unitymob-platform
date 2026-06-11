module AccessAudit
  class DeviceParser
    def self.call(user_agent)
      new(user_agent).call
    end

    def initialize(user_agent)
      @user_agent = user_agent.to_s
    end

    def call
      {
        device_type: device_type,
        browser: browser,
        platform: platform
      }
    end

    private

    attr_reader :user_agent

    def device_type
      return "Tablet" if user_agent.match?(/ipad|tablet/i)
      return "Celular" if user_agent.match?(/mobile|iphone|android/i)

      "Computador"
    end

    def browser
      return "Edge" if user_agent.match?(/Edg\//)
      return "Chrome" if user_agent.match?(/Chrome\//) && !user_agent.match?(/Chromium\//)
      return "Safari" if user_agent.match?(/Safari\//) && !user_agent.match?(/Chrome\//)
      return "Firefox" if user_agent.match?(/Firefox\//)

      "Navegador não identificado"
    end

    def platform
      return "iOS" if user_agent.match?(/iPhone|iPad|iPod/i)
      return "Android" if user_agent.match?(/Android/i)
      return "macOS" if user_agent.match?(/Mac OS X|Macintosh/i)
      return "Windows" if user_agent.match?(/Windows/i)
      return "Linux" if user_agent.match?(/Linux/i)

      "Sistema não identificado"
    end
  end
end
