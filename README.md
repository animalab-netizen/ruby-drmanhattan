# ruby-drmanhattan

`ruby-drmanhattan` is the Ruby runtime for the DrManhattan family.

It adapts the same observability concepts to Ruby applications while keeping the API idiomatic to the language.

## Status

- gem: `ruby-drmanhattan`
- repository: `ruby-drmanhattan`
- status: `implemented`

## Covered contract

- `Event`
- `EventObserver`
- `EventEnricher`
- `DefaultEventBus`
- `EventFactory`
- `CommonMetadata`
- `CommonMetadataEnricher`
- `Protocol`
- `ProtocolEndpoint`
- `ProtocolMessage`
- `ProtocolFailure`
- `ProtocolClose`
- `ProtocolSessionTracker`
- `WebSocketSessionTracker`
- `DrManhattan`

## Install

```bash
gem install ruby-drmanhattan
```

## Example

```ruby
require "ruby_drmanhattan"

bus = RubyDrManhattan::DefaultEventBus.new
factory = RubyDrManhattan::EventFactory.new(
  metadata: RubyDrManhattan::CommonMetadata.new("1.0.0", platform: "ruby", environment: "prod")
)
dr = RubyDrManhattan::DrManhattan.new(bus, factory)

observer = Object.new
observer.define_singleton_method(:on_event) do |event|
  p [event.name, event.attributes]
end

bus.subscribe(observer)

endpoint = RubyDrManhattan::ProtocolEndpoint.new(
  "chat",
  address: "wss://socket.example.com",
  channel: "rooms/general"
)

dr.screen_viewed("Home")
dr.web_socket_connection_started(endpoint, "ws-42")
dr.web_socket_message_sent(
  endpoint,
  operation: "join_room",
  type: "json",
  correlation_id: "corr-1",
  session_id: "ws-42"
)
```

## Development

```bash
ruby test/runtime_test.rb
```
