# frozen_string_literal: true

class SubscriptionClientSupplier < ActiveRecord::Base
  has_many :resources, foreign_key: "supplier_id", class_name: "SubscriptionClientResource", dependent: :destroy
  has_many :subscriptions, through: :resources
  has_many :notices, class_name: "SubscriptionClientNotice", as: :notice_subject, dependent: :destroy

  belongs_to :user

  scope :authorized, -> { where("api_key IS NOT NULL") }

  def destroy_authorization
    if SubscriptionClient::Authorization.revoke(self)
      update(api_key: nil, user_id: nil, authorized_at: nil)
      deactivate_all_subscriptions!
      true
    else
      false
    end
  end

  def authorized?
    api_key.present?
  end

  def deactivate_all_subscriptions!
    subscriptions.update_all(subscribed: false)
  end

  def self.publish_authorized_supplier_count
    payload = { authorized_supplier_count: authorized.count }
    group_id_key = SiteSetting.subscription_client_allow_moderator_subscription_management ? :staff : :admins
    MessageBus.publish("/subscription_client", payload, group_ids: [Group::AUTO_GROUPS[group_id_key.to_sym]])
  end
end

# == Schema Information
#
# Table name: subscription_client_suppliers
#
#  id            :bigint           not null, primary key
#  name          :string
#  url           :string           not null
#  api_key       :string
#  user_id       :bigint
#  authorized_at :datetime
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_subscription_client_suppliers_on_url      (url) UNIQUE
#  index_subscription_client_suppliers_on_user_id  (user_id)
#
