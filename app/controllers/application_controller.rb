class ApplicationController < ActionController::Base
  protect_from_forgery
  helper_method :current_user_is_admin?, :page_title,
    :can_see_admin_menu?

  # set_year_from_params() should run first because it
  # defines @year which other methods depend on.
  before_filter :set_year_from_params
  before_filter :set_yearly_vars
  before_filter :set_display_timezone

  def default_url_options(options={})

    # TODO: When running functional tests or controller specs, default_url_options()
    # is called before callbacks.  This may be a regression of issue 2031.
    # https://github.com/rails/rails/issues/2031
    # The ugly workaround is to manually invoke the required callback.
    set_year_from_params unless @year.present?

    { :year => @year.year }
  end

  def set_display_timezone
    Time.zone = @year.timezone
  end

  def set_year_from_params

    # In 2011 we used the constant CONGRESS_YEAR to determine the
    # current year, but going forward we will use params[:year] in most
    # places. Hopefully, when this transition is complete we will be
    # able to drop the constant.
    if params[:year].present?
      year = params[:year].to_i
    else
      year = CONGRESS_YEAR.to_i
    end

    # Validate year to protect against sql injection, or benign
    # programmer error.
    raise "Invalid year" unless (2011..2100).include?(year)

    # Load year object
    @year = Year.find_by_year(year)
    raise "Year #{year} not found" unless @year.present?
  end

  def set_yearly_vars

    # Define a range of all expected years
    # Currently just used for year navigation in footer
    @years = 2011..LATEST_YEAR

    # Location and date range
    @congress_city = @year.city
    @congress_state = @year.state
    @congress_date_range = @year.date_range

    # The layout needs a list of content and activity categories
    @content_categories_for_menu = ContentCategory.yr(@year).order(:name)
    @activity_categories_for_menu = ActivityCategory.yr(@year).order(:name)
    @tournaments_for_nav_menu = Tournament.yr(@year).nav_menu
  end

  # Redirect Devise to a specific page after successful sign in
  def after_sign_in_path_for(resource_or_scope)
    if resource_or_scope.is_a?(User)
      resource_or_scope.after_sign_in_path
    else
      super
    end
  end

  rescue_from CanCan::AccessDenied do |exception|
    # Rails.logger.debug exception.subject.inspect
    render_access_denied
  end

protected

  def human_action_name
    (action_name == "index") ? 'List' : action_name.titleize
  end

  # `model_class` returns the constant that refers to the model associated
  # with this controller.  If there is no associated model, return nil.
  # eg. UsersController.model_class() returns User
  # eg. ReportsController.model_class() returns nil
  def model_class
    controller_name.classify.constantize rescue nil
  end

  # `human_controller_name` is a bit of a misnomer, since it actually
  # returns the associated model name if it can, otherwise it just chops
  # off the string "Controller" from itself and returns the remainder.
  def human_controller_name
    if model_class.respond_to?(:model_name)
      model_class.model_name.human
    else
      controller_name.singularize.titleize
    end
  end

  def page_title
    case action_name
    when "index"
      return human_controller_name.pluralize.titleize
    when "new", "edit"
      return human_action_name + ' ' + human_controller_name
    when "show"
      return human_controller_name + ' Details'
    else
      return human_controller_name + ' ' + human_action_name
    end
  end

  def current_user_is_admin?
    current_user.present? && current_user.is_admin?
  end

  def allow_only_admin
    unless current_user && current_user.is_admin?
      render_access_denied
    end
  end

  def allow_only_self_or_admin
    target_user_id = params[:id].to_i
    unless current_user && (current_user.id.to_i == target_user_id || current_user.is_admin?)
      render_access_denied
    end
  end

  def deny_users_from_wrong_year
    render_access_denied unless current_user && current_user.year == @year.year
  end

private

  def render_access_denied
    # A friendlier "access denied" message -Jared 2010.1.2
    @deny_message = user_signed_in? ? 'You are signed in, but' : 'You are not signed in, so of course'
    @deny_message += ' you do not have permission to '
    @deny_message += (action_name == "index") ? 'list all' : action_name
    @deny_message += ' ' + controller_name
    @deny_message += ' (or perhaps just this particular ' + controller_name.singularize + ').'

    # Alf says: render or redirect and the filter chain stops there
    render 'home/access_denied', :status => :forbidden
  end

  def can_see_admin_menu?
    can?(:see_admin_menu, :layout) && current_user.year == @year.year
  end

end
