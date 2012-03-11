require "sinatra"
require "sinatra/reloader" if development?
require "mogli"
require "RMagick"
include Magick
require "base64"

enable :sessions
set :raise_errors, false
set :show_exceptions, false

FACEBOOK_SCOPE = ''
unless ENV["FACEBOOK_APP_ID"] && ENV["FACEBOOK_SECRET"]
  abort("missing env vars: please set FACEBOOK_APP_ID and FACEBOOK_SECRET with your app credentials")
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
end

# the facebook session expired! reset ours and restart the process
error(Mogli::Client::HTTPException) do
  session[:at] = nil
  redirect "/auth/facebook"
end

get %r{/(\d*)$} do
  redirect "/auth/facebook" unless session[:at]
  @client = Mogli::Client.new(session[:at])

  # limit queries to 15 results
  @client.default_params[:limit] = 500

  @size = 32
  @app  = Mogli::Application.find(ENV["FACEBOOK_APP_ID"], @client)
  @user = Mogli::User.find("me", @client)

  @friends = @user.friends.sort_by{rand}.slice(0..25)
  @colors = [];
  @friend = params[:captures].first;
  @friend = @user.id if @friend.empty?;
  @name = Mogli::User.find(@friend, @client).name

  res = HTTParty::get 'http://graph.facebook.com/'+@friend+'/picture'
  img = (Image.from_blob res.body)[0]
  img.resize!(@size, @size);

  (0..@size**2-1).each do |px|
    @colors = @colors.push img.pixel_color(px%@size, (px/@size).floor).intensity/65535.to_f
  end

  @large = []
  while @large.length<16 do
    x = rand(@size-1); y = rand(@size-1)
    @large.push([x,y]) if !@large.any? { |l| (l[0]-x).abs<2 && (l[1]-y).abs<2 }
  end
  
  @imgs = []
  @friends.each do |f|
    res = HTTParty::get 'http://graph.facebook.com/'+f.id+'/picture'
    img = (Image.from_blob res.body)[0]
    img.resize!(40,40)
    value = img.resize(1,1).pixel_color(1,1).intensity/65535.to_f
    @imgs.push :data=>Base64.encode64(img.to_blob {self.format="gif"}), :value=>value, :id=>f.id
  end

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
