# frozen_string_literal: true

module RSpec
  module Rails
    module Matchers
      # Container module for event reporter matchers.
      #
      # @api private
      module EventReporter
        # @api private
        # Internal subscriber that collects events during test execution.
        module EventCollector
          @subscribed = false
          @mutex = Mutex.new

          class << self
            def emit(event)
              event_recorders&.each do |recorder|
                recorder << Event.new(event)
              end
              true
            end

            def record
              subscribe
              events = []
              event_recorders << events
              begin
                yield
                events
              ensure
                event_recorders.delete_if { |r| events.equal?(r) }
              end
            end

            private

            def subscribe
              return if @subscribed

              @mutex.synchronize do
                unless @subscribed
                  if ActiveSupport.event_reporter
                    ActiveSupport.event_reporter.subscribe(self)
                    @subscribed = true
                  else
                    raise "No event reporter is configured. Ensure Rails.application is initialized."
                  end
                end
              end
            end

            def event_recorders
              ActiveSupport::IsolatedExecutionState[:rspec_rails_event_reporter_events] ||= []
            end
          end
        end

        # @api private
        # Wraps event data and provides matching logic.
        class Event
          attr_reader :event_data

          def initialize(event_data)
            @event_data = event_data
          end

          def inspect
            "#{event_data[:name]} (payload: #{event_data[:payload].inspect}, tags: #{event_data[:tags].inspect})"
          end

          def matches?(name, payload = nil, tags = nil)
            return false if name && name.to_s != event_data[:name]
            return false if payload && !matches_payload?(payload)
            return false if tags && !matches_tags?(tags)

            true
          end

          private

          def matches_payload?(expected_payload)
            matches_hash?(expected_payload, :payload, allow_regexp: false)
          end

          def matches_tags?(expected_tags)
            matches_hash?(expected_tags, :tags, allow_regexp: true)
          end

          def matches_hash?(expected, key, allow_regexp:)
            actual = event_data[key]
            return false unless actual.is_a?(Hash)

            expected.all? do |k, v|
              return false unless actual.key?(k)

              actual_value = actual[k]
              if allow_regexp && v.is_a?(Regexp)
                actual_value.to_s.match?(v)
              else
                actual_value == v
              end
            end
          end
        end

        # @api private
        # Base class for event reporter matchers.
        class Base < RSpec::Rails::Matchers::BaseMatcher
          def supports_value_expectations?
            false
          end

          def supports_block_expectations?
            true
          end
        end

        # @api private
        #
        # Matcher class for `have_reported_event`. Should not be instantiated directly.
        #
        # @see RSpec::Rails::Matchers#have_reported_event
        class HaveReportedEvent < Base
          def initialize(expected_name)
            super()
            @expected_name = expected_name
            @expected_payload = nil
            @expected_tags = nil
          end

          # @api public
          # Specifies the expected payload
          #
          # @param payload [Hash] expected payload keys and values
          # @return [HaveReportedEvent] self for chaining
          # @raise [ArgumentError] if payload is not a Hash
          def with_payload(payload)
            unless payload.is_a?(Hash)
              raise ArgumentError, "with_payload requires a Hash, got #{payload.class}"
            end

            @expected_payload = payload
            self
          end

          # @api public
          # Specifies the expected tags (supports Regexp values)
          #
          # @param tags [Hash] expected tag keys and values (values can be Regexp)
          # @return [HaveReportedEvent] self for chaining
          # @raise [ArgumentError] if tags is not a Hash
          def with_tags(tags)
            unless tags.is_a?(Hash)
              raise ArgumentError, "with_tags requires a Hash, got #{tags.class}"
            end

            @expected_tags = tags
            self
          end

          def matches?(block)
            @events = EventCollector.record(&block)

            if @events.empty?
              @failure_reason = :no_events
              return false
            end

            @matching_event = @events.find do |event|
              event.matches?(@expected_name, @expected_payload, @expected_tags)
            end

            if @matching_event
              true
            else
              @failure_reason = :no_match
              false
            end
          end

          def failure_message
            case @failure_reason
            when :no_events
              "expected an event to be reported, but there were no events reported"
            when :no_match
              lines = ["expected an event to be reported matching:"]
              lines << "  name: #{@expected_name.inspect}" if @expected_name
              lines << "  payload: #{@expected_payload.inspect}" if @expected_payload
              lines << "  tags: #{@expected_tags.inspect}" if @expected_tags
              lines << "but none of the #{@events.size} reported event(s) matched:"
              lines.concat(@events.map { |e| "  #{e.inspect}" })
              lines.join("\n")
            end
          end

          def failure_message_when_negated
            if @expected_name
              "expected no event matching #{@expected_name.inspect} to be reported, but one was found"
            else
              "expected no event to be reported, but one was found"
            end
          end

          def description
            desc = "report event"
            desc += " #{@expected_name.inspect}" if @expected_name
            desc += " with payload #{@expected_payload.inspect}" if @expected_payload
            desc += " with tags #{@expected_tags.inspect}" if @expected_tags
            desc
          end
        end
      end

      # @api public
      # Passes if the block reports an event matching the expected name.
      #
      # @example Basic usage
      #   expect { Rails.event.notify("user.created", { id: 123 }) }
      #     .to have_reported_event("user.created")
      #
      # @example With payload matching
      #   expect { Rails.event.notify("user.created", { id: 123, name: "John" }) }
      #     .to have_reported_event("user.created")
      #     .with_payload(id: 123)
      #
      # @example With tags matching (supports Regexp)
      #   expect {
      #     Rails.event.tagged(request_id: "abc123") do
      #       Rails.event.notify("user.created", { id: 123 })
      #     end
      #   }.to have_reported_event("user.created")
      #     .with_tags(request_id: /[a-z0-9]+/)
      #
      # @param name [String, Symbol] the expected event name
      # @return [HaveReportedEvent]
      def have_reported_event(name = nil)
        EventReporter::HaveReportedEvent.new(name)
      end
    end
  end
end
