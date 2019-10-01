# frozen_string_literal: true

require "spec_helper"

describe "Identity document request edition", type: :system do
  let(:organization) do
    create(
      :organization,
      available_authorizations: ["unique_identity"],
      unique_identity_methods: [:online]
    )
  end

  let(:verification_method) { :online }
  let!(:authorization) do
    create(
      :authorization,
      :pending,
      name: "unique_identity",
      user: user,
      verification_metadata: {
        "verification_type" => verification_method,
        "document_type" => "DNI",
        "document_number" => "XXXXXXXX",
        "last_name" => "El Foo",
        "first_name" => "Bar",
        "birth_date" => "12/04/1994",
        "birth_place" => "Dummy"
      },
      verification_attachment: Decidim::Dev.test_file("id.jpg", "image/jpg")
    )
  end

  let!(:user) { create(:user, :confirmed, organization: organization) }

  before do
    switch_to_host(organization.host)
    login_as user, scope: :user
    visit decidim_verifications.authorizations_path
    click_link "Unique identity"
  end

  context "when the organization only has online method active" do
    it "allows the user to change the data" do
      expect(page).to have_selector("form", text: "Request verification again")

      submit_upload_form(
        doc_type: "DNI",
        doc_number: "XXXXXXXY",
        residence_doc_type: "Energy bill",
        city_resident: true,
        file_name: "dni.jpg"
      )
      expect(page).to have_content("Document successfully reuploaded")
      authorization.reload
      expect(authorization.verification_metadata["verification_type"]).to eq "online"
      expect(authorization.verification_metadata["document_number"]).to eq "XXXXXXXY"
    end
  end

  context "when the organization only has offline method active" do
    let!(:organization) do
      create(
        :organization,
        available_authorizations: ["unique_identity"],
        unique_identity_methods: [:offline],
        unique_identity_explanation_text: { en: "This is my explanation text" }
      )
    end
    let(:verification_method) { :offline }

    it "allows the user to change the data" do
      expect(page).to have_selector("form", text: "Request verification again")
      expect(page).not_to have_content("Scanned copy of your document")
      expect(page).to have_content("This is my explanation text")

      submit_upload_form(
        doc_type: "DNI",
        doc_number: "XXXXXXXY",
        residence_doc_type: "Energy bill",
        city_resident: true
      )
      expect(page).to have_content("Document successfully reuploaded")
      authorization.reload
      expect(authorization.verification_metadata["verification_type"]).to eq "offline"
      expect(authorization.verification_metadata["document_number"]).to eq "XXXXXXXY"
    end
  end

  context "when the organization has both online and offline methods active" do
    let!(:organization) do
      create(
        :organization,
        available_authorizations: ["unique_identity"],
        unique_identity_methods: [:offline, :online],
        unique_identity_explanation_text: { en: "This is my explanation text" }
      )
    end

    context "when the authorization is offline" do
      let(:verification_method) { :offline }

      it "allows the user to change the verification method" do
        expect(page).to have_selector("form", text: "Request verification again")
        expect(page).not_to have_content("Scanned copy of your document")
        click_link "Use online verification"

        submit_upload_form(
          doc_type: "DNI",
          doc_number: "XXXXXXXY",
          residence_doc_type: "Energy bill",
          city_resident: true,
          file_name: "dni.jpg"
        )

        expect(page).to have_content("Document successfully reuploaded")
        authorization.reload
        expect(authorization.verification_metadata["verification_type"]).to eq "online"
        expect(authorization.verification_metadata["document_number"]).to eq "XXXXXXXY"
        expect(authorization.verification_attachment).to be_present
      end
    end

    context "when the authorization is online" do
      let(:verification_method) { :online }

      it "allows the user to change the verification method" do
        expect(page).to have_selector("form", text: "Request verification again")
        click_link "Use offline verification"
        expect(page).not_to have_content("Scanned copy of your document")

        submit_upload_form(
          doc_type: "DNI",
          doc_number: "XXXXXXXY",
          residence_doc_type: "Energy bill",
          city_resident: true
        )

        expect(page).to have_content("Document successfully reuploaded")
        authorization.reload
        expect(authorization.verification_metadata["verification_type"]).to eq "offline"
        expect(authorization.verification_metadata["document_number"]).to eq "XXXXXXXY"
        expect(authorization.verification_attachment).to be_present
      end
    end
  end

  private

  def submit_upload_form(doc_type:, doc_number:, residence_doc_type:, city_resident:, file_name: nil)
    select doc_type, from: "Type of your document"
    fill_in "Document number (with letter)", with: doc_number
    select residence_doc_type, from: "Residence document type"
    check "City resident" if city_resident
    attach_file "Scanned copy of your document", Decidim::Dev.asset(file_name) if file_name

    click_button "Request verification again"
  end
end
