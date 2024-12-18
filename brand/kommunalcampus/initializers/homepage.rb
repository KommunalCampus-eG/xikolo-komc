# frozen_string_literal: true

Rails.application.config.homepage_course_loader = proc do
  current_and_upcoming = Catalog::Category::CurrentAndUpcoming.new

  current_and_upcoming.courses.any? ? [Home::Category.new(current_and_upcoming)] : []
end
