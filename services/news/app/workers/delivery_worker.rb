# frozen_string_literal: true

class DeliveryWorker
  include Sidekiq::Job

  def perform(id, user)
    delivery = Delivery.find(id)

    Delivery::Send.call(delivery, user)
  end

  class << self
    def call(delivery, user)
      perform_async(delivery.id, user.as_json.slice('id', 'email', 'language'))
    end
  end
end
