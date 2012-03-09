require "sinatra"
require "sinatra/reloader" if development?
require "mogli"
require "RMagick"
include Magick

enable :sessions
set :raise_errors, false
set :show_exceptions, false

# Scope defines what permissions that we are asking the user to grant.
# In this example, we are asking for the ability to publish stories
# about using the app, access to what the user likes, and to be able
# to use their pictures.  You should rewrite this scope with whatever
# permissions your app needs.
# See https://developers.facebook.com/docs/reference/api/permissions/
# for a full list of permissions
FACEBOOK_SCOPE = 'user_likes,user_photos,user_photo_video_tags'

unless ENV["FACEBOOK_APP_ID"] && ENV["FACEBOOK_SECRET"]
  abort("missing env vars: please set FACEBOOK_APP_ID and FACEBOOK_SECRET with your app credentials")
end

before do
  # HTTPS redirect
  if settings.environment == :production && request.scheme != 'https'
    redirect "https://#{request.env['HTTP_HOST']}"
  end
end

helpers do
  def url(path)
    base = "#{request.scheme}://#{request.env['HTTP_HOST']}"
    base + path
  end

  def post_to_wall_url
    "https://www.facebook.com/dialog/feed?redirect_uri=#{url("/close")}&display=popup&app_id=#{@app.id}";
  end

  def send_to_friends_url
    "https://www.facebook.com/dialog/send?redirect_uri=#{url("/close")}&display=popup&app_id=#{@app.id}&link=#{url('/')}";
  end

  def authenticator
    @authenticator ||= Mogli::Authenticator.new(ENV["FACEBOOK_APP_ID"], ENV["FACEBOOK_SECRET"], url("/auth/facebook/callback"))
  end

  def first_column(item, collection)
    return ' class="first-column"' if collection.index(item)%4 == 0
  end
end

# the facebook session expired! reset ours and restart the process
error(Mogli::Client::HTTPException) do
  session[:at] = nil
  redirect "/auth/facebook"
end

get "/" do
  redirect "/auth/facebook" unless session[:at]
  @client = Mogli::Client.new(session[:at])

  # limit queries to 15 results
  @client.default_params[:limit] = 15

  @size = 32
  @app  = Mogli::Application.find(ENV["FACEBOOK_APP_ID"], @client)
  @user = Mogli::User.find("me", @client)

  @friends = @user.friends[0, 1]
  @colors = [];
  @friends.each do |friend|
    res = HTTParty::get 'https://graph.facebook.com/'+friend.id+'/picture'
    img = (Image.from_blob res.body)[0]
    img.resize!(@size, @size);

    (0..@size**2-1).each do |px|
      @colors = @colors.push img.pixel_color(px%@size, (px/@size).floor).intensity
    end
  end
  logger.info @colors
  erb :index
end

# used by Canvas apps - redirect the POST to be a regular GET
post "/" do
  redirect "/"
end

# used to close the browser window opened to post to wall/send to friends
get "/close" do
  "<body onload='window.close();'/>"
end

get "/auth/facebook" do
  session[:at]=nil
  redirect authenticator.authorize_url(:scope => FACEBOOK_SCOPE, :display => 'page')
end

get '/auth/facebook/callback' do
  client = Mogli::Client.create_from_code_and_authenticator(params[:code], authenticator)
  session[:at] = client.access_token
  redirect '/'
end
