# frozen_string_literal: true

require 'bundler'
Bundler.require

# require 'sinatra'
require 'sinatra/base'
require 'sinatra/activerecord'
require 'sqlite3'
require_relative 'models/archive'
require_relative 'models/download'

set :bind, '0.0.0.0'
set :public_folder, 'public'
set :logger, Logger.new(STDOUT) # STDOUT & STDERR is captured by unicorn
# logger.info("Logger initialized...")

# Define the route for the main page
get '/' do
  # Display the list of content_keys
  erb :index, locals: { archives: Archive.all }
end

get '/downloads/new' do
  erb :create_download
end

# Define the route for handling the form submission to add a new row (changed endpoint to /download)
post '/downloads/new' do
  # Insert a new row into the archive_downloads table
  Archive.create(key: params[:content_key], status: 'analyzing')

  # Redirect back to the main page after adding a new row
  redirect '/'
end

# Define the route for individual content_key details (showing form for editing)
get '/downloads/:id' do
  # Display the details on the content_key-specific page
  scope = Archive.where(params[:id])
  unless params[:status].nil?
    scope = scope.includes(:downloads).where(downloads: {status: params[:status]})
  end
  erb :view_download, locals: { archive: scope.first }
end

# Define the route for handling the form submission to edit details
patch '/downloads/:id/edit' do
  Archive.find(params[:id]).update!(priority: params[:priority])
end

get '/downloads/:id/scan' do
  archive = Archive.includes(:downloads)
                   .where(id: params[:id])
                   .where.not(downloads: { status: 'downloaded' })
                   .first

  archive.validate_against_disk

  redirect "/downloads/#{params[:id]}?status=pending"
end

get '/downloads/:id/delete' do
  Archive.find_by(id: params[:id])&.destroy
  redirect '/'
end

# Close the database connection when the application exits
# at_exit do
#   db.close if db
# end

# Start the Sinatra web server
# run Sinatra::Application
