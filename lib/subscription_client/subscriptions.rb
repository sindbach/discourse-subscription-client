# frozen_string_literal: true

class SubscriptionClient::Subscriptions
  def initialize
    @suppliers = SubscriptionClientSupplier.authorized
  end

  def self.update
    new.update
  end

  def update
    return if !SiteSetting.subscription_client_enabled

    @result = SubscriptionClient::Subscriptions::Result.new

    if @suppliers.blank?
      @result.no_suppliers
    else
      @suppliers.each do |supplier|
        update_supplier(supplier)
      end
    end

    if @result.errors.any?
      @result.errors.each do |error|
        Rails.logger.error "SubscriptionClient::Subscriptions.update: #{error}"
      end
    end

    if SiteSetting.subscription_client_verbose_logs && @result.infos.any?
      @result.infos.each do |info|
        Rails.logger.info "SubscriptionClient::Subscriptions.update: #{info}"
      end
    end

    @result.errors.blank?
  end

  def update_supplier(supplier)
    resources = supplier.resources
    return unless resources.present?

    request = SubscriptionClient::Request.new(:supplier, supplier.id)
    headers = { "User-Api-Key" => supplier.api_key }
    url = "#{supplier.url}/subscription-server/user-subscriptions"

    response = request.perform(url, headers: headers, body: { resources: resources.map(&:name) })
    return (supplier.deactivate_all_subscriptions! && @result.connection_error(supplier)) if response.nil?

    subscription_data = @result.retrieve_subscriptions(supplier, response)
    return supplier.deactivate_all_subscriptions! if @result.errors.any?

    # deactivate any of the supplier's subscriptions not retrieved from supplier
    if supplier.subscriptions.present?
      supplier.subscriptions.each do |subscription|
        has_match = false
        subscription_data.each do |data|
          if data_matches_subscription(data, subscription)
            data.subscription = subscription
            has_match = true
          end
        end
        subscription.deactivate! unless has_match
      end
    end

    return @result.no_subscriptions(supplier) if subscription_data.blank?

    subscription_data.each do |data|
      if data.subscription.present?
        data.subscription.update(subscribed: true)
        data.subscription.touch

        @result.updated_subscription(supplier, subscription_ids: data.required)
      else
        subscription = SubscriptionClientSubscription.create!(data.create.merge(subscribed: true))

        if subscription
          @result.created_subscription(supplier, subscription_ids: data.required)
        else
          @result.failed_to_create_subscription(supplier, subscription_ids: data.required)
        end
      end
    end
  end

  def data_matches_subscription(data, subscription)
    data.required.all? { |k, v| subscription.send(k.to_s) == v }
  end
end
