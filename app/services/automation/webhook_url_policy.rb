require "ipaddr"
require "resolv"
require "uri"

module Automation
  # Centralized SSRF guard for automation webhook egress.
  #
  # A destination is allowed only when it is an http(s) URL without embedded
  # credentials whose host resolves exclusively to public IP addresses.
  # Loopback, private, link-local, multicast and reserved ranges are rejected,
  # including every address returned for a DNS name (no first-answer shortcut).
  #
  # Hosts that do not resolve to any address are allowed through: with no
  # resolved address the HTTP client cannot route the request anywhere, so the
  # delivery fails naturally instead of hitting an internal target.
  module WebhookUrlPolicy
    BLOCKED_MESSAGE = "Blocked webhook destination".freeze

    RESERVED_RANGES = [
      "0.0.0.0/8",
      "100.64.0.0/10",
      "192.0.2.0/24",
      "192.88.99.0/24",
      "198.18.0.0/15",
      "198.51.100.0/24",
      "203.0.113.0/24",
      "224.0.0.0/4",
      "240.0.0.0/4",
      "255.255.255.255/32",
      "::/128",
      "::ffff:0:0/96",
      "64:ff9b::/96",
      "100::/64",
      "2001::/32",
      "2001:db8::/32",
      "2002::/16",
      "fc00::/7",
      "fe80::/10",
      "ff00::/8"
    ].map { |cidr| IPAddr.new(cidr) }.freeze

    module_function

    def blocked?(raw_url)
      !allowed?(raw_url)
    end

    def allowed?(raw_url)
      uri = parse(raw_url)
      return false if uri.nil?
      return false unless %w[http https].include?(uri.scheme.to_s.downcase)
      return false if uri.userinfo.present?

      host = uri.host.to_s.strip
      return false if host.blank?

      addresses = resolve(host)
      return true if addresses.empty?

      addresses.none? { |ip| blocked_ip?(ip) }
    end

    def parse(raw_url)
      str = raw_url.to_s.strip
      return nil if str.blank?

      URI.parse(str)
    rescue URI::InvalidURIError
      nil
    end

    def resolve(host)
      literal = try_parse_ip(host)
      return [literal] if literal

      Resolv.getaddresses(host).filter_map { |addr| try_parse_ip(addr) }
    rescue StandardError
      []
    end

    def try_parse_ip(value)
      IPAddr.new(value)
    rescue ArgumentError
      nil
    end

    def blocked_ip?(ip)
      return true if ip.loopback? || ip.private? || ip.link_local?
      return true if RESERVED_RANGES.any? { |range| range.include?(ip) }

      false
    rescue ArgumentError
      true
    end
  end
end
