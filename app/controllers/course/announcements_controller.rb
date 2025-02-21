# frozen_string_literal: true

class Course::AnnouncementsController < Abstract::FrontendController
  include Interruptible

  include CourseContextHelper
  inside_course

  def index
    Acfs.run # because of `inside_course`

    @posts = news_service.rel(:news_index).get(
      {
        course_id: the_course.id,
        published: !current_user.allowed?('news.announcement.show'),
        language: I18n.locale,
      }
    ).value!.map do |post|
      AnnouncementPresenter.create post
    end
    @course_presenter = CoursePresenter.create(@course = the_course, current_user)

    set_page_title(the_course.title, t(:'courses.nav.announcements'))
  end

  def new
    authorize! 'news.announcement.create'
    Acfs.run # because of `inside_course`

    @announcement = Course::Admin::AnnouncementForm.new
  end

  def edit
    authorize! 'news.announcement.update'
    Acfs.run # because of `inside_course`

    @announcement = news_service
      .rel(:news)
      .get(id: params[:id])
      .then do |announcement|
      check_access! announcement

      Course::Admin::AnnouncementForm.from_resource(announcement)
    end.value!
  end

  def create
    authorize! 'news.announcement.create'
    Acfs.run # because of `inside_course`

    @announcement = Course::Admin::AnnouncementForm.from_params(params)

    # re-render the creation form if the announcement is invalid or the user does not have permission to send emails
    return render(action: :new) unless @announcement.valid? && can_send_emails?

    news_service
      .rel(:news_index)
      .post(@announcement.to_resource.merge(
        'course_id' => course_id,
        'author_id' => current_user.id,
        'notification' => params[:notification]
      )).value!

    add_flash_message(:success, t(:'flash.success.announcement_saved'))
    redirect_to(action: :index)
  rescue Restify::UnprocessableEntity => e
    @announcement.remote_errors e.errors

    # re-render creation form
    render(action: :new)
  end

  def update
    authorize! 'news.announcement.update'
    Acfs.run # because of `inside_course`

    @announcement = Course::Admin::AnnouncementForm.from_params(params)
    @announcement.persisted!

    announcement = news_service.rel(:news).get(id: params[:id]).value!
    check_access! announcement

    # re-render edit form if announcement is invalid
    return render(action: :edit) unless @announcement.valid?

    announcement
      .rel(:self)
      .patch(@announcement.to_resource.merge(
        'notification' => params[:notification]
      )).value!

    add_flash_message(:success, t(:'flash.success.announcement_saved'))
    redirect_to course_announcements_path
  rescue Restify::UnprocessableEntity => e
    @announcement.remote_errors e.errors

    # re-render edit form
    render(action: :edit)
  end

  def destroy
    authorize! 'news.announcement.delete'
    Acfs.run # because of `inside_course`

    announcement = news_service.rel(:news).get(id: params[:id]).value!
    check_access! announcement

    announcement.rel(:self).delete.value!

    redirect_to course_announcements_path
  end

  def hide_course_nav?
    # Only show the course nav in the learner-facing page (the index page)
    @_action_name != 'index'
  end

  private

  def auth_context
    the_course.context_id
  end

  def course_id
    the_course.id
  end

  def check_access!(announcement)
    return if [announcement['course_id'], the_course.course_code].include? params[:course_id]

    raise Status::Unauthorized
  end

  def can_send_emails?
    return current_user.allowed?('news.announcement.send') if params[:notification] == 'send'
    return current_user.allowed?('news.announcement.send_test') if params[:notification] == 'test'

    true
  end

  def email_params
    if params[:notification] == 'test'
      {test_receiver: current_user.id}
    else
      {}
    end
  end

  def news_service
    @news_service ||= Xikolo.api(:news).value!
  end
end
