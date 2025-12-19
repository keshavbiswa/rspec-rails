RSpec.describe "have_reported_event", skip: !RSpec::Rails::FeatureCheck.has_event_reporter? do
  describe "basic name matching" do
    it "passes when event is reported" do
      expect { Rails.event.notify("user.created", { id: 123 }) }.to have_reported_event("user.created")
    end

    it "passes with symbol event name" do
      expect { Rails.event.notify(:user_created, { id: 123 }) }.to have_reported_event("user_created")
    end

    it "fails when no events are reported" do
      expect {
        expect { }.to have_reported_event("user.created")
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /no events reported/)
    end

    it "fails when event name doesn't match" do
      expect {
        expect {
          Rails.event.notify("user.updated", { id: 123 })
        }.to have_reported_event("user.created")
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /none of the 1 reported event\(s\) matched/)
    end
  end
end
