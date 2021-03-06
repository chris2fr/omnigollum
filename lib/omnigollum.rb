require 'cgi'
require 'omniauth'
require 'mustache/sinatra'
require 'sinatra/base'

module Omnigollum
  module Views; class Layout < Mustache; end; end
  module Models
    class OmniauthUserInitError < StandardError; end

    class User
      attr_reader :uid, :name, :email, :nickname, :provider
    end

    class OmniauthUser < User
      def initialize (hash, options)
        # Validity checks, don't trust providers
        @uid = hash['uid'].to_s.strip
        raise OmniauthUserInitError, "Pas compris // Insufficient data from authentication provider, uid not provided or empty" if @uid.empty?

        @name = hash['info']['name'].to_s.strip if hash['info'].has_key?('name')
        @name = options[:default_name] if !@name || @name.empty?

        raise OmniauthUserInitError, "Pas compris // Insufficient data from authentication provider, name not provided or empty" if !@name || @name.empty?

        @email = hash['info']['email'].to_s.strip if hash['info'].has_key?('email')
        @email = options[:default_email] if !@email || @email.empty?

        raise OmniauthUserInitError, "Pas compris // Insufficient data from authentication provider, email not provided or empty" if !@email || @email.empty?

        @nickname = hash['info']['nickname'].to_s.strip if hash['info'].has_key?('nickname')

        @provider = hash['provider']

        @groups = get_groups(@uid, options)

        self
      end
    end
  end

  module Helpers
    def check_action(action, route)
      if action != :read && !user_authed?
        user_auth
      end
      user = session[:omniauth_user]
      scan_path = settings.gollum_path
      allowed = false
      if route == '/fileview'
        folders = []
      else
        folders = params[:path] && params[:path].split('/') || params[:splat] && params[:splat][0].split('/') || []
        folders.shift if folders[0] == route.gsub(/\/\*/, '')
      end
      while true
        perms = find_permissions(scan_path)
        if user
          all_groups = user.groups + [user.email, 'Known']
        else
          all_groups = ['All']
        end
        all_groups.each do |group|
          (perms[action] || []).each do |perm|
            if perm == group || perm.match(/\/(.*)\//) && group.match(Regexp.new(perm[1..-2]))
              allowed = true
              return
            end
          end
        end
        break if folders.empty?
        scan_path = ::File.expand_path(folders.shift, scan_path)
        break unless ::File.directory?(scan_path)
      end
      unless allowed
        if user_authed?
          halt 403, "Forbidden: you do not have sufficient privileges for this action! (#{action}). You may ask a wiki administrator to give you the right for #{action} in the auth.md ACL file of the page directory or of some parent directory. You belong to the following groups: #{all_groups.inspect}"
        else
          user_auth
        end
      end
    end

    def find_permissions(path) #TODO implement some kind of caching may be? Also look at Gollum::Page#find_sub_page
      if File.directory?(path) && Dir.entries(path).index("auth.md")
        content = ::File.open(::File.expand_path('auth.md', path), 'rb').read
        content.gsub(/\<\!--+\s+---(.*?)---+\s+--\>/m) do #Embedded yaml metadata as Gollum used to support
#         yaml = @wiki.sanitizer.clean($1)
          yaml = $1
          hash = YAML.load(yaml)
          if Hash === hash
            return hash
          else
            return {}
          end
        end
      else
        return {}
      end
    end

    def user_authed?
      session.has_key? :omniauth_user
    end

    def user_auth
      @title   = 'Authentication is required // Authentification requise'
      @subtext = 'Please choose a login service // Merci de choisir un mode d\'identification'
      show_login
    end

    def kick_back
      redirect !request.referrer.nil? && request.referrer !~ /#{Regexp.escape(settings.send(:omnigollum)[:route_prefix])}\/.*/ ?
        request.referrer:
        '/'
      halt
    end

    def get_user
      session[:omniauth_user]
    end

    def user_deauth
      session.delete :omniauth_user
    end

    def auth_config
      options = settings.send(:omnigollum)

      @auth = {
        :route_prefix => options[:route_prefix],
        :providers    => options[:provider_names],
        :path_images  => options[:path_images],
        :logo_suffix  => options[:logo_suffix],
        :logo_missing => options[:logo_missing]
      }
    end

    def show_login
      options = settings.send(:omnigollum)

      # Don't bother showing the login screen, just redirect
      if options[:provider_names].count == 1
        if !request.params['origin'].nil?
          origin = request.params['origin']
        elsif !request.path.nil?
          origin = request.path
        else
          origin = '/'
        end

        redirect (request.script_name || '') + options[:route_prefix] + '/auth/' + options[:provider_names].first.to_s + "?origin=" +
           CGI.escape(origin)
      else
         auth_config
         require options[:path_views] + '/login'
         halt mustache Omnigollum::Views::Login
      end
    end

    def show_error
      options = settings.send(:omnigollum)
      auth_config
      require options[:path_views] + '/error'
      halt mustache Omnigollum::Views::Error
    end

    def commit_message
      if user_authed?
        user = get_user
        return { :message => params[:message], :name => user.name, :email => user.email}
      else
        return { :message => params[:message]}
      end
    end
  end

  # Config class provides default values for omnigollum configuration, and an array
  # of all providers which have been enabled if a omniauth config block is passed to
  # eval_omniauth_config.
  class Config
    attr_accessor :default_options
    class << self; attr_accessor :default_options; end

    @default_options = {
      # # Gollum 4 uses /create, /create/*, etc, while Gollum 5 uses
      # # /gollum/create, /gollum/create/*, etc.  Protect both by
      # # default so that omnigollum works with either out of the box.
      # :protected_routes => [
      #                       'create',
      #                       'delete',
      #                       'edit',
      #                       'rename',
      #                       'revert',
      #                       'upload',
      #                      ].map { |x|
      #   ["/#{x}", "/#{x}/*"].map { |y|
      #     [y, "/gollum#{y}"]
      #   }
      # }.flatten,
      :check_acl => false,
      :protected_create_routes => [
        '/create/*',
        '/create',
      ],
      :protected_read_routes => [
        '/*',
        '/data/*',
        '/history/*',
        '/compare/*',
        '/preview', #FIXME? *
#        '/search',
        '/fileview'],
      :protected_update_routes => [
        '/edit/*',
        '/edit',
        '/rename/*',
        '/revert/*',
        '/revert'],
      :protected_delete_routes => [
        '/delete/*',
        '/delete'],
      :route_prefix => '/__omnigollum__',
      :dummy_auth   => true,
      :providers    => Proc.new { provider :github, '', '' },
      :path_base    => dir = File.expand_path(File.dirname(__FILE__) + '/..'),
      :logo_suffix  => "_logo.png",
      :logo_missing => "omniauth", # Set to false to disable missing logos
      :path_images  => "#{dir}/public/images",
      :path_views   => "#{dir}/views",
      :path_templates => "#{dir}/templates",
      :default_name   => nil,
      :default_email  => nil,
      :provider_names => [],
      :authorized_users => [],
      :author_format => Proc.new { |user| user.nickname ? user.name + ' (' + user.nickname + ')' : user.name },
      :author_email => Proc.new { |user| user.email }
    }
    @default_options[:protected_routes] = @default_options[:protected_update_routes] + @default_options[:protected_create_routes] + @default_options[:protected_delete_routes]

    def initialize
      @default_options = self.class.default_options
    end

    # Register provider name
    #
    # name - Provider symbol
    # args - Arbitrary arguments
    def provider(name, *args)
      @default_options[:provider_names].push name
    end

    # Evaluate procedure calls in an omniauth config block/proc in the context
    # of this class.
    #
    # This allows us to learn about omniauth config items that would otherwise be inaccessible.
    #
    # block - Omniauth proc or block
    def eval_omniauth_config(&block)
      self.instance_eval(&block)
    end

    # Catches missing methods we haven't implemented, but which omniauth accepts
    # in its config block.
    #
    # args - Arbitrary list of arguments
    def method_missing(*args); end
  end

  module Sinatra
    def self.registered(app)
      # As options determine which routes are created, they must be set before registering omniauth
      config  = Omnigollum::Config.new

      options = app.settings.respond_to?(:omnigollum) ?
        config.default_options.merge(app.settings.send(:omnigollum)) :
        config.default_options

      # Set omniauth path prefix based on options
      OmniAuth.config.path_prefix = options[:route_prefix] + OmniAuth.config.path_prefix

      # Setup test_mode options
      if options[:dummy_auth]
        OmniAuth.config.test_mode = true
        OmniAuth.config.mock_auth[:default] = {
          'uid' => '12345',
          "info" => {
            "email"  => "user@example.com",
            "name"   => "example user"
            },
            'provider' => 'local'
          }
        end
      # Register helpers
      app.helpers Helpers

      # Enable sinatra session support
      app.set :sessions,  true
            # Enable sinatra session support
            # app.use Rack::Session::Cookie

      # Setup omniauth providers
      if !options[:providers].nil?
        app.use OmniAuth::Builder, &options[:providers]

        # You told omniauth, now tell us!
        config.eval_omniauth_config &options[:providers] if options[:provider_names].count == 0
      end

      # Populates instance variables used to display currently logged in user
      app.before '/*' do
        # @omnigollum_enabled = true  # chris2fr FIXME
        @user_authed = user_authed?
        @user        = get_user
      end

      # Stop browsers from screwing up our referrer information
      # FIXME: This is hacky...
      app.before '/favicon.ico' do
        halt 403 unless user_authed?
      end

      # Explicit login (user followed login link) clears previous redirect info
      app.before options[:route_prefix] + '/login' do
        kick_back if user_authed?
        @auth_params = "?origin=#{CGI.escape(request.referrer)}" unless request.referrer.nil?
        user_auth
      end

      app.before options[:route_prefix] + '/logout' do
        user_deauth
        kick_back
      end

      app.before options[:route_prefix] + '/auth/failure' do
        user_deauth
        @title    = 'Echec // Authentication failed'
        @subtext = "L\'authorité choisi ne vous reconnait point. Essayer, peut-être avec une autre. // Provider did not validate your credentials (#{params[:message]}) - please retry or choose another login service"
        @auth_params = "?origin=#{CGI.escape(request.env['omniauth.origin'])}" unless request.env['omniauth.origin'].nil?
        show_error
      end

      app.before options[:route_prefix] + '/auth/:name/callback' do
        begin
          if !request.env['omniauth.auth'].nil?
            user = Omnigollum::Models::OmniauthUser.new(request.env['omniauth.auth'], options)

            case (authorized_users = options[:authorized_users])
            when Regexp
              user_authorized = (user.email =~ authorized_users)
            when Array
              user_authorized = authorized_users.include?(user.email) || authorized_users.include?(user.nickname)
            else
              user_authorized = true
            end

            # Check authorized users
            if !user_authorized
              @title   = 'Authorization failed // Echec d\'authorisation'
              @subtext = 'User was not found in the authorized users list // Vous n\'êtes pas sur la liste'
              @auth_params = "?origin=#{CGI.escape(request.env['omniauth.origin'])}" unless request.env['omniauth.origin'].nil?
              show_error
            end

            session[:omniauth_user] = user

            # Update gollum's author hash, so commits are recorded correctly
            session['gollum.author'] = {
              :name => options[:author_format].call(user),
              :email => options[:author_email].call(user)
            }

            redirect request.env['omniauth.origin']
          elsif !user_authed?
            @title   = 'Echec // Authentication failed'
            @subtext = 'Erreur interne à moi // Omniauth experienced an error processing your request'
            @auth_params = "?origin=#{CGI.escape(request.env['omniauth.origin'])}" unless request.env['omniauth.origin'].nil?
            show_error
          end
        rescue StandardError => fail_reason
          @title   = 'Echec // Authentication failed'
          @subtext = fail_reason
          @auth_params = "?origin=#{CGI.escape(request.env['omniauth.origin'])}" unless request.env['omniauth.origin'].nil?
          show_error
        end
      end

      app.before options[:route_prefix] + '/images/:image.png' do
        content_type :png
        send_file options[:path_images] + '/' + params[:image] + '.png'
      end

      # Stop sinatra processing and hand off to omniauth
      app.before options[:route_prefix] + '/auth/:provider' do
        halt 404
      end

      # # Pre-empt protected routes
      # options[:protected_routes].each {|route| app.before(route) {user_auth unless user_authed?}}

            # Pre-empt protected routes
            [:create, :update, :delete].each do |action|
              route_group = "protected_#{action}_routes".to_sym
              options[route_group].each do |route|
                app.before(route) do
                  if options[:check_acl]
                    check_action(action, route)
                  else
                    user_auth unless user_authed?
                  end
                end
              end
            end
      
            # Pre-empt read routes, but only if ACL mode is enabled
            if options[:check_acl]
              route_group = :protected_read_routes
              options[route_group].each do |route|
                app.before(route) do
                  check_action(:read, route)
                end
              end
            end

      # Write the actual config back to the app instance
      app.set(:omnigollum, options)
    end
  end
end
