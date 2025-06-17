# frozen_string_literal: true

class OrganizationDecorator < ApplicationDecorator
  delegate_all

  def as_json(opts = {})
    {
      id: model.id,
      name: model.name,
    }.as_json(opts)
  end
end
