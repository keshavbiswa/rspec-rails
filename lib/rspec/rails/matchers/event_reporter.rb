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
              event_recorders&.each do |events|
                events << Event.new(event)
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
            "#{event_data[:name]} (payload: #{event_data[:payload].inspect})"
          end

          def matches?(name)
            return true if name.nil?

            name.to_s == event_data[:name]
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
          end

          def matches?(block)
            @events = EventCollector.record(&block)

            if @events.empty?
              @failure_reason = :no_events
              return false
            end

            @matching_event = @events.find do |event|
              event.matches?(@expected_name)
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
              message = "expected an event to be reported matching:\n"
              message += "  name: #{@expected_name.inspect}\n"
              message += "but none of the #{@events.size} reported event(s) matched:\n"
              message += @events.map { |e| "  #{e.inspect}" }.join("\n")
              message
            end
          end

          def description
            "report event #{@expected_name.inspect}"
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
      # @param name [String, Symbol] the expected event name
      # @return [HaveReportedEvent]
      def have_reported_event(name = nil)
        EventReporter::HaveReportedEvent.new(name)
      end
    end
  end
end
