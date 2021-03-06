# frozen_string_literal: true

require "spec_helper"

describe Decidim::Proposals::Admin::UpdateProposal do
  let(:form_klass) { Decidim::Proposals::Admin::ProposalForm }

  let(:component) { create(:proposal_component) }
  let(:organization) { component.organization }
  let(:user) { create :user, :admin, :confirmed, organization: organization }
  let(:form) do
    form_klass.from_params(
      form_params
    ).with_context(
      current_organization: organization,
      current_participatory_space: component.participatory_space,
      current_user: user,
      current_component: component
    )
  end

  let!(:proposal) { create :proposal, :official, component: component }

  let(:has_address) { false }
  let(:address) { nil }
  let(:attachment_params) { nil }
  let(:uploaded_photos) { [] }
  let(:current_photos) { [] }
  let(:latitude) { 40.1234 }
  let(:longitude) { 2.1234 }

  describe "call" do
    let(:form_params) do
      {
        title: "A reasonable proposal title",
        body: "A reasonable proposal body",
        address: address,
        has_address: has_address,
        attachment: attachment_params,
        photos: current_photos,
        add_photos: uploaded_photos
      }
    end

    let(:command) do
      described_class.new(form, proposal)
    end

    describe "when the form is not valid" do
      before do
        expect(form).to receive(:invalid?).and_return(true)
      end

      it "broadcasts invalid" do
        expect { command.call }.to broadcast(:invalid)
      end

      it "doesn't update the proposal" do
        expect do
          command.call
        end.not_to change(proposal, :title)
      end
    end

    describe "when the form is valid" do
      it "broadcasts ok" do
        expect { command.call }.to broadcast(:ok)
      end

      it "updates the proposal" do
        expect do
          command.call
        end.to change(proposal, :title)
      end

      it "traces the update", versioning: true do
        expect(Decidim.traceability)
          .to receive(:update!)
          .with(proposal, user, a_kind_of(Hash))
          .and_call_original

        expect { command.call }.to change(Decidim::ActionLog, :count)

        action_log = Decidim::ActionLog.last
        expect(action_log.version).to be_present
        expect(action_log.version.event).to eq "update"
      end

      context "when geocoding is enabled" do
        let(:component) { create(:proposal_component, :with_geocoding_enabled) }

        context "when the has address checkbox is checked" do
          let(:has_address) { true }

          context "when the address is present" do
            let(:address) { "Carrer Pare Llaurador 113, baixos, 08224 Terrassa" }

            before do
              stub_geocoding(address, [latitude, longitude])
            end

            it "sets the latitude and longitude" do
              command.call
              proposal = Decidim::Proposals::Proposal.last

              expect(proposal.latitude).to eq(latitude)
              expect(proposal.longitude).to eq(longitude)
            end
          end
        end
      end

      context "when attachments are allowed", processing_uploads_for: Decidim::AttachmentUploader do
        let(:component) { create(:proposal_component, :with_attachments_allowed) }
        let(:attachment_params) do
          {
            title: "My attachment",
            file: Decidim::Dev.test_file("city.jpeg", "image/jpeg")
          }
        end

        it "creates an atachment for the proposal" do
          expect { command.call }.to change(Decidim::Attachment, :count).by(1)
          last_proposal = Decidim::Proposals::Proposal.last
          last_attachment = Decidim::Attachment.last
          expect(last_attachment.attached_to).to eq(last_proposal)
        end

        context "when attachment is left blank" do
          let(:attachment_params) do
            {
              title: ""
            }
          end

          it "broadcasts ok" do
            expect { command.call }.to broadcast(:ok)
          end
        end
      end

      context "when galleries are allowed", processing_uploads_for: Decidim::AttachmentUploader do
        let(:component) { create(:proposal_component, :with_attachments_allowed) }
        let(:attachment_params) do
          {
            title: ""
          }
        end
        let(:uploaded_photos) do
          [
            Decidim::Dev.test_file("city.jpeg", "image/jpeg"),
            Decidim::Dev.test_file("city.jpeg", "image/jpeg")
          ]
        end

        it "creates a gallery for the proposal" do
          expect { command.call }.to change(Decidim::Attachment, :count).by(2)
          proposal = Decidim::Proposals::Proposal.last
          expect(proposal.photos.count).to eq(2)
          last_attachment = Decidim::Attachment.last
          expect(last_attachment.attached_to).to eq(proposal)
        end

        context "when gallery is left blank" do
          let(:uploaded_photos) { [] }

          it "broadcasts ok" do
            expect { command.call }.to broadcast(:ok)
          end
        end

        context "when photos are removed" do
          let!(:proposal) { create :proposal, :official, component: component }
          let!(:photo1) do
            create(:attachment, :with_image, attached_to: proposal)
          end
          let!(:photo2) do
            create(:attachment, :with_image, attached_to: proposal)
          end
          let(:attachment_params) do
            {
              title: ""
            }
          end
          let(:uploaded_photos) { [] }
          let(:current_photos) do
            [photo1.id.to_s]
          end

          it "to decrease the number of photos in the gallery" do
            expect(proposal.attachments.count).to eq(2)
            expect(proposal.photos.count).to eq(2)
            expect { command.call }.to change(Decidim::Attachment, :count).by(-1)
            expect(proposal.attachments.count).to eq(1)
            expect(proposal.photos.count).to eq(1)
          end
        end
      end
    end
  end
end
