# frozen_string_literal: true

class Section::Destroy < ApplicationOperation
  attr_reader :section

  def initialize(section)
    super()

    @section = section
  end

  def call
    ActiveRecord::Base.transaction do
      if section.parent?
        section.children.each do |child|
          Section::Destroy.call(child)
        end
      end

      section.destroy
    end
  end
end
