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

  describe "with payload matching" do
    it "passes with matching payload" do
      expect {
        Rails.event.notify("user.created", { id: 123, name: "John" })
      }.to have_reported_event("user.created").with_payload(id: 123)
    end

    it "passes with partial payload matching" do
      expect {
        Rails.event.notify("user.created", { id: 123, name: "John", email: "john@example.com" })
      }.to have_reported_event("user.created").with_payload(id: 123, name: "John")
    end

    it "fails when payload doesn't match" do
      expect {
        expect {
          Rails.event.notify("user.created", { id: 456 })
        }.to have_reported_event("user.created").with_payload(id: 123)
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /none of the 1 reported event\(s\) matched/)
    end
  end
end
