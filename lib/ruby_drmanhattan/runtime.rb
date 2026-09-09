# frozen_string_literal: true

module RubyDrManhattan
  def self.merge_attributes(*parts)
    parts.compact.reduce({}) { |merged, part| merged.merge(part) }
  end

  class Event
    attr_reader :name, :attributes

    def initialize(name, attributes = {})
      @name = name
      @attributes = attributes.dup.freeze
      freeze
    end

    def with_attribute(key, value)
      self.class.new(name, RubyDrManhattan.merge_attributes(attributes, { key => value }))
    end

    def with_attributes(values)
      self.class.new(name, RubyDrManhattan.merge_attributes(attributes, values))
    end
  end

  module EventObserver
    def on_event(_event)
      raise NotImplementedError
    end
  end

  module EventEnricher
    def enrich(_event)
      raise NotImplementedError
    end
  end

  class DefaultEventBus
    def initialize(enrichers: [], on_observer_error: nil)
      @observers = []
      @enrichers = enrichers.dup.freeze
      @on_observer_error = on_observer_error
    end

    def subscribe(observer)
      @observers << observer
    end

    def unsubscribe(observer)
      @observers.delete(observer)
    end

    def publish(event)
      enriched = @enrichers.reduce(event) { |current, enricher| enricher.enrich(current) }

      @observers.dup.each do |observer|
        observer.on_event(enriched)
      rescue StandardError => e
        @on_observer_error&.call(observer, enriched, e)
      end
    end
  end

  class CommonMetadata
    attr_reader :app_version, :platform, :environment, :extra

    def initialize(app_version, platform: nil, environment: nil, extra: {})
      @app_version = app_version
      @platform = platform
      @environment = environment
      @extra = extra.dup.freeze
      freeze
    end

    def as_attributes
      attributes = { "app.version" => app_version }
      attributes["platform"] = platform unless platform.nil?
      attributes["environment"] = environment unless environment.nil?
      RubyDrManhattan.merge_attributes(attributes, extra).freeze
    end
  end

  class CommonMetadataEnricher
    include EventEnricher

    def initialize(metadata)
      @metadata = metadata
      freeze
    end

    def enrich(event)
      event.with_attributes(@metadata.as_attributes)
    end
  end

  class HttpError
    attr_reader :code, :type, :message

    def initialize(code, type: nil, message: nil)
      @code = code
      @type = type
      @message = message
      freeze
    end
  end

  class Protocol
    attr_reader :name

    def initialize(name)
      @name = name
      freeze
    end

    HTTP = new("http")
    WEB_SOCKET = new("websocket")
    SERVER_SENT_EVENTS = new("sse")
    GRPC = new("grpc")
    MQTT = new("mqtt")
    TCP = new("tcp")
    UDP = new("udp")
  end

  class ProtocolEndpoint
    attr_reader :name, :address, :channel

    def initialize(name, address: nil, channel: nil)
      @name = name
      @address = address
      @channel = channel
      freeze
    end

    def as_attributes
      attributes = { "endpoint.name" => name }
      attributes["endpoint.address"] = address unless address.nil?
      attributes["endpoint.channel"] = channel unless channel.nil?
      attributes.freeze
    end
  end

  module ProtocolMessageDirection
    INBOUND = "inbound"
    OUTBOUND = "outbound"
  end

  class ProtocolMessage
    attr_reader :direction, :operation, :type, :correlation_id, :size_bytes, :attributes

    def initialize(direction, operation: nil, type: nil, correlation_id: nil, size_bytes: nil, attributes: {})
      @direction = direction
      @operation = operation
      @type = type
      @correlation_id = correlation_id
      @size_bytes = size_bytes
      @attributes = attributes.dup.freeze
      freeze
    end

    def as_attributes
      mapped = { "message.direction" => direction }
      mapped["message.operation"] = operation unless operation.nil?
      mapped["message.type"] = type unless type.nil?
      mapped["message.correlation_id"] = correlation_id unless correlation_id.nil?
      mapped["message.size_bytes"] = size_bytes.to_s unless size_bytes.nil?
      RubyDrManhattan.merge_attributes(mapped, attributes).freeze
    end
  end

  class ProtocolFailure
    attr_reader :code, :type, :message, :retryable, :attributes

    def initialize(code: nil, type: nil, message: nil, retryable: nil, attributes: {})
      @code = code
      @type = type
      @message = message
      @retryable = retryable
      @attributes = attributes.dup.freeze
      freeze
    end

    def as_attributes
      mapped = {}
      mapped["error.code"] = code unless code.nil?
      mapped["error.type"] = type unless type.nil?
      mapped["error.message"] = message unless message.nil?
      mapped["error.retryable"] = retryable.to_s unless retryable.nil?
      RubyDrManhattan.merge_attributes(mapped, attributes).freeze
    end
  end

  class ProtocolClose
    attr_reader :code, :reason, :graceful, :attributes

    def initialize(code: nil, reason: nil, graceful: nil, attributes: {})
      @code = code
      @reason = reason
      @graceful = graceful
      @attributes = attributes.dup.freeze
      freeze
    end

    def as_attributes
      mapped = {}
      mapped["close.code"] = code.to_s unless code.nil?
      mapped["close.reason"] = reason unless reason.nil?
      mapped["close.graceful"] = graceful.to_s unless graceful.nil?
      RubyDrManhattan.merge_attributes(mapped, attributes).freeze
    end
  end

  class EventFactory
    def initialize(metadata: nil, custom_enrichers: [])
      @enrichers = custom_enrichers.dup
      @enrichers.unshift(CommonMetadataEnricher.new(metadata)) unless metadata.nil?
      @enrichers.freeze
    end

    def screen_viewed(screen_name)
      enrich(Event.new("screen_viewed", { "screen.name" => screen_name }))
    end

    def tap(screen_name, action)
      enrich(Event.new("tap", { "screen.name" => screen_name, "event.action" => action }))
    end

    def http_error(screen_name, error)
      attributes = {
        "screen.name" => screen_name,
        "error.code" => error.code.to_s
      }
      attributes["error.type"] = error.type unless error.type.nil?
      attributes["error.message"] = error.message unless error.message.nil?
      enrich(Event.new("http_error", attributes))
    end

    def custom(name, attributes = {})
      enrich(Event.new(name, attributes))
    end

    def protocol_connection_started(protocol, endpoint, session_id = nil, attributes = {})
      enrich_protocol_event("protocol_connection_started", protocol, endpoint, session_id, attributes)
    end

    def protocol_connection_opened(protocol, endpoint, session_id = nil, attributes = {})
      enrich_protocol_event("protocol_connection_opened", protocol, endpoint, session_id, attributes)
    end

    def protocol_message(protocol, endpoint, message, session_id = nil)
      enrich_protocol_event("protocol_message", protocol, endpoint, session_id, message.as_attributes)
    end

    def protocol_connection_closed(protocol, endpoint, close = ProtocolClose.new, session_id = nil)
      enrich_protocol_event("protocol_connection_closed", protocol, endpoint, session_id, close.as_attributes)
    end

    def protocol_failure(protocol, endpoint, failure, session_id = nil)
      enrich_protocol_event("protocol_failure", protocol, endpoint, session_id, failure.as_attributes)
    end

    def protocol_reconnect_scheduled(protocol, endpoint, attempt, delay_millis, reason = nil, session_id = nil, attributes = {})
      reconnect_attributes = {
        "reconnect.attempt" => attempt.to_s,
        "reconnect.delay_ms" => delay_millis.to_s
      }
      reconnect_attributes["reconnect.reason"] = reason unless reason.nil?
      enrich_protocol_event(
        "protocol_reconnect_scheduled",
        protocol,
        endpoint,
        session_id,
        RubyDrManhattan.merge_attributes(reconnect_attributes, attributes)
      )
    end

    def web_socket_connection_started(endpoint, session_id = nil, attributes = {})
      protocol_connection_started(Protocol::WEB_SOCKET, endpoint, session_id, attributes)
    end

    def web_socket_connection_opened(endpoint, session_id = nil, attributes = {})
      protocol_connection_opened(Protocol::WEB_SOCKET, endpoint, session_id, attributes)
    end

    def web_socket_message_sent(endpoint, operation: nil, type: nil, correlation_id: nil, size_bytes: nil, session_id: nil, attributes: {})
      protocol_message(
        Protocol::WEB_SOCKET,
        endpoint,
        ProtocolMessage.new(
          ProtocolMessageDirection::OUTBOUND,
          operation: operation,
          type: type,
          correlation_id: correlation_id,
          size_bytes: size_bytes,
          attributes: attributes
        ),
        session_id
      )
    end

    def web_socket_message_received(endpoint, operation: nil, type: nil, correlation_id: nil, size_bytes: nil, session_id: nil, attributes: {})
      protocol_message(
        Protocol::WEB_SOCKET,
        endpoint,
        ProtocolMessage.new(
          ProtocolMessageDirection::INBOUND,
          operation: operation,
          type: type,
          correlation_id: correlation_id,
          size_bytes: size_bytes,
          attributes: attributes
        ),
        session_id
      )
    end

    def web_socket_connection_closed(endpoint, close = ProtocolClose.new, session_id = nil)
      protocol_connection_closed(Protocol::WEB_SOCKET, endpoint, close, session_id)
    end

    def web_socket_failure(endpoint, failure, session_id = nil)
      protocol_failure(Protocol::WEB_SOCKET, endpoint, failure, session_id)
    end

    def web_socket_reconnect_scheduled(endpoint, attempt, delay_millis, reason = nil, session_id = nil, attributes = {})
      protocol_reconnect_scheduled(Protocol::WEB_SOCKET, endpoint, attempt, delay_millis, reason, session_id, attributes)
    end

    private

    def enrich(event)
      @enrichers.reduce(event) { |current, enricher| enricher.enrich(current) }
    end

    def enrich_protocol_event(name, protocol, endpoint, session_id, attributes)
      mapped = RubyDrManhattan.merge_attributes(
        { "protocol.name" => protocol.name },
        endpoint.as_attributes,
        attributes
      )
      mapped["session.id"] = session_id unless session_id.nil?
      enrich(Event.new(name, mapped))
    end
  end

  class DrManhattan
    def initialize(bus, factory)
      @bus = bus
      @factory = factory
    end

    def publish(event)
      @bus.publish(event)
    end

    def screen_viewed(screen_name)
      publish(@factory.screen_viewed(screen_name))
    end

    def tap(screen_name, action)
      publish(@factory.tap(screen_name, action))
    end

    def http_error(screen_name, error)
      publish(@factory.http_error(screen_name, error))
    end

    def custom(name, attributes = {})
      publish(@factory.custom(name, attributes))
    end

    def protocol_connection_started(protocol, endpoint, session_id = nil, attributes = {})
      publish(@factory.protocol_connection_started(protocol, endpoint, session_id, attributes))
    end

    def protocol_connection_opened(protocol, endpoint, session_id = nil, attributes = {})
      publish(@factory.protocol_connection_opened(protocol, endpoint, session_id, attributes))
    end

    def protocol_message(protocol, endpoint, message, session_id = nil)
      publish(@factory.protocol_message(protocol, endpoint, message, session_id))
    end

    def protocol_connection_closed(protocol, endpoint, close = ProtocolClose.new, session_id = nil)
      publish(@factory.protocol_connection_closed(protocol, endpoint, close, session_id))
    end

    def protocol_failure(protocol, endpoint, failure, session_id = nil)
      publish(@factory.protocol_failure(protocol, endpoint, failure, session_id))
    end

    def protocol_reconnect_scheduled(protocol, endpoint, attempt, delay_millis, reason = nil, session_id = nil, attributes = {})
      publish(@factory.protocol_reconnect_scheduled(protocol, endpoint, attempt, delay_millis, reason, session_id, attributes))
    end

    def web_socket_connection_started(endpoint, session_id = nil, attributes = {})
      publish(@factory.web_socket_connection_started(endpoint, session_id, attributes))
    end

    def web_socket_connection_opened(endpoint, session_id = nil, attributes = {})
      publish(@factory.web_socket_connection_opened(endpoint, session_id, attributes))
    end

    def web_socket_message_sent(endpoint, operation: nil, type: nil, correlation_id: nil, size_bytes: nil, session_id: nil, attributes: {})
      publish(
        @factory.web_socket_message_sent(
          endpoint,
          operation: operation,
          type: type,
          correlation_id: correlation_id,
          size_bytes: size_bytes,
          session_id: session_id,
          attributes: attributes
        )
      )
    end

    def web_socket_message_received(endpoint, operation: nil, type: nil, correlation_id: nil, size_bytes: nil, session_id: nil, attributes: {})
      publish(
        @factory.web_socket_message_received(
          endpoint,
          operation: operation,
          type: type,
          correlation_id: correlation_id,
          size_bytes: size_bytes,
          session_id: session_id,
          attributes: attributes
        )
      )
    end

    def web_socket_connection_closed(endpoint, close = ProtocolClose.new, session_id = nil)
      publish(@factory.web_socket_connection_closed(endpoint, close, session_id))
    end

    def web_socket_failure(endpoint, failure, session_id = nil)
      publish(@factory.web_socket_failure(endpoint, failure, session_id))
    end

    def web_socket_reconnect_scheduled(endpoint, attempt, delay_millis, reason = nil, session_id = nil, attributes = {})
      publish(@factory.web_socket_reconnect_scheduled(endpoint, attempt, delay_millis, reason, session_id, attributes))
    end

    def protocol_session(protocol, endpoint, session_id = nil)
      ProtocolSessionTracker.new(self, protocol, endpoint, session_id)
    end

    def web_socket_session(endpoint, session_id = nil)
      WebSocketSessionTracker.new(self, endpoint, session_id)
    end
  end

  class ProtocolSessionTracker
    attr_reader :endpoint, :session_id

    def initialize(dr_manhatan, protocol, endpoint, session_id = nil)
      @dr_manhatan = dr_manhatan
      @protocol = protocol
      @endpoint = endpoint
      @session_id = session_id
    end

    def connection_started(attributes = {})
      @dr_manhatan.protocol_connection_started(@protocol, endpoint, session_id, attributes)
    end

    def connection_opened(attributes = {})
      @dr_manhatan.protocol_connection_opened(@protocol, endpoint, session_id, attributes)
    end

    def message(message)
      @dr_manhatan.protocol_message(@protocol, endpoint, message, session_id)
    end

    def inbound_message(operation: nil, type: nil, correlation_id: nil, size_bytes: nil, attributes: {})
      message(
        ProtocolMessage.new(
          ProtocolMessageDirection::INBOUND,
          operation: operation,
          type: type,
          correlation_id: correlation_id,
          size_bytes: size_bytes,
          attributes: attributes
        )
      )
    end

    def outbound_message(operation: nil, type: nil, correlation_id: nil, size_bytes: nil, attributes: {})
      message(
        ProtocolMessage.new(
          ProtocolMessageDirection::OUTBOUND,
          operation: operation,
          type: type,
          correlation_id: correlation_id,
          size_bytes: size_bytes,
          attributes: attributes
        )
      )
    end

    def heartbeat_sent(correlation_id = nil, attributes = {})
      outbound_message(
        operation: "heartbeat",
        type: "heartbeat",
        correlation_id: correlation_id,
        attributes: attributes
      )
    end

    def heartbeat_received(correlation_id = nil, attributes = {})
      inbound_message(
        operation: "heartbeat",
        type: "heartbeat",
        correlation_id: correlation_id,
        attributes: attributes
      )
    end

    def reconnect_scheduled(attempt, delay_millis, reason = nil, attributes = {})
      @dr_manhatan.protocol_reconnect_scheduled(
        @protocol,
        endpoint,
        attempt,
        delay_millis,
        reason,
        session_id,
        attributes
      )
    end

    def failure(failure)
      @dr_manhatan.protocol_failure(@protocol, endpoint, failure, session_id)
    end

    def closed(close = ProtocolClose.new)
      @dr_manhatan.protocol_connection_closed(@protocol, endpoint, close, session_id)
    end
  end

  class WebSocketSessionTracker < ProtocolSessionTracker
    def initialize(dr_manhatan, endpoint, session_id = nil)
      super(dr_manhatan, Protocol::WEB_SOCKET, endpoint, session_id)
    end
  end
end
