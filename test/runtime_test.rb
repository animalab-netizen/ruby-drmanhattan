# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/ruby_drmanhattan"

module RubyDrManhattan
  class Recorder
    include EventObserver

    attr_reader :events

    def initialize
      @events = []
    end

    def on_event(event)
      @events << event
    end
  end

  class RuntimeTest < Minitest::Test
    def test_event_factory_enriches_common_metadata
      factory = EventFactory.new(
        metadata: CommonMetadata.new("1.0.0", platform: "ruby", environment: "prod")
      )

      event = factory.custom("custom_event", { "feature" => "chat" })

      assert_equal "custom_event", event.name
      assert_equal "chat", event.attributes["feature"]
      assert_equal "1.0.0", event.attributes["app.version"]
      assert_equal "ruby", event.attributes["platform"]
      assert_equal "prod", event.attributes["environment"]
    end

    def test_default_event_bus_keeps_order_and_isolates_observer_failure
      deliveries = []
      errors = []

      failing = Object.new
      failing.define_singleton_method(:on_event) do |event|
        deliveries << "first"
        raise event.name
      end

      success = Object.new
      success.define_singleton_method(:on_event) do |_event|
        deliveries << "second"
      end

      bus = DefaultEventBus.new(
        on_observer_error: lambda do |_observer, _event, error|
          errors << error
        end
      )

      bus.subscribe(failing)
      bus.subscribe(success)
      bus.publish(Event.new("ordered"))

      assert_equal ["first", "second"], deliveries
      assert_equal 1, errors.length
      assert_instance_of RuntimeError, errors.first
    end

    def test_drmanhattan_publishes_websocket_lifecycle_and_failure_events
      recorder = Recorder.new
      bus = DefaultEventBus.new
      bus.subscribe(recorder)

      tracker = DrManhattan.new(
        bus,
        EventFactory.new(metadata: CommonMetadata.new("1.0.0"))
      )

      endpoint = ProtocolEndpoint.new(
        "chat",
        address: "wss://socket.example.com",
        channel: "rooms/general"
      )

      tracker.web_socket_connection_started(endpoint, "ws-42")
      tracker.web_socket_message_sent(
        endpoint,
        operation: "join_room",
        type: "json",
        correlation_id: "corr-1",
        session_id: "ws-42"
      )
      tracker.web_socket_failure(
        endpoint,
        ProtocolFailure.new(
          code: "WS_TIMEOUT",
          type: "transport",
          message: "heartbeat timeout",
          retryable: true
        ),
        "ws-42"
      )

      assert_equal 3, recorder.events.length
      assert_equal "protocol_connection_started", recorder.events[0].name
      assert_equal "outbound", recorder.events[1].attributes["message.direction"]
      assert_equal "join_room", recorder.events[1].attributes["message.operation"]
      assert_equal "protocol_failure", recorder.events[2].name
      assert_equal "true", recorder.events[2].attributes["error.retryable"]
    end

    def test_protocol_session_tracker_emits_heartbeat_and_reconnect_events
      recorder = Recorder.new
      bus = DefaultEventBus.new
      bus.subscribe(recorder)

      tracker = DrManhattan.new(bus, EventFactory.new)
      session = tracker.protocol_session(
        Protocol::MQTT,
        ProtocolEndpoint.new("broker"),
        "mqtt-9"
      )

      session.heartbeat_sent("hb-out-1")
      session.heartbeat_received("hb-in-1")
      session.reconnect_scheduled(2, 1500, "network_lost")
      session.closed(ProtocolClose.new(code: 1001, reason: "going away", graceful: false))

      assert_equal 4, recorder.events.length
      assert_equal "heartbeat", recorder.events[0].attributes["message.operation"]
      assert_equal "outbound", recorder.events[0].attributes["message.direction"]
      assert_equal "inbound", recorder.events[1].attributes["message.direction"]
      assert_equal "2", recorder.events[2].attributes["reconnect.attempt"]
      assert_equal "1001", recorder.events[3].attributes["close.code"]
    end

    def test_http_error_maps_screen_and_error_attributes
      event = EventFactory.new.http_error(
        "Checkout",
        HttpError.new(503, type: "maintenance", message: "temporarily unavailable")
      )

      assert_equal "http_error", event.name
      assert_equal "Checkout", event.attributes["screen.name"]
      assert_equal "503", event.attributes["error.code"]
      assert_equal "maintenance", event.attributes["error.type"]
    end
  end
end
