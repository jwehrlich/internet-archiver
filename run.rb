#!/usr/bin/env ruby

# frozen_string_literal: true

require 'concurrent'
require 'etc'
require 'nokogiri'
require 'open-uri'
require 'optparse'
require 'tty-progressbar'
require_relative 'lib/download'

class Archiver
  MAX_QUEUE_SIZE = 5
  MAX_THREAD_COUNT = Etc.nprocessors - 1

  class << self
    def download(options)
      instance = new(options)
      instance.process
    end
  end

  def initialize(options)
    @content_key = options[:content_key]
    @filter_ext_match = options[:filter_ext_match]&.split(',')&.collect(&:strip)
    @filter_ext_exclusion = options[:filter_ext_exclusion]&.split(',')&.collect(&:strip)
    @progress_bars = TTY::ProgressBar::Multi.new('Archive.org [:bar] :rate MiB/s :elapsed', frequency: 2)

    FileUtils.mkdir_p('logs')
    @logger = Logger.new('logs/archiver.log')
    @logger.level = Logger::WARN

    # Register a signal handler to clean up temp files on termination
    # Signal.trap('INT') do
    #   puts 'Script terminated by user. Cleaning up...'
    #   cleanup_tempfiles
    #   exit
    # end
  end

  def cleanup_tempfiles
    download_folder = "download/"
    files = find_files_with_extension(download_folder, ".download")
    pp files
    # File.delete(@temp_path) if @temp_path && File.exist?(@temp_path)
  end

  def find_files_with_extension(start_path, extension)
    files = []

    Dir.foreach(start_path) do |entry|
      next if entry == '.' || entry == '..'

      full_path = File.join(start_path, entry)

      if File.directory?(full_path)
        # Recursively search in subdirectories
        files.concat(find_files_with_extension(full_path, extension))
      elsif entry.end_with?(extension)
        files << full_path
      end
    end

    files
  end

  def process
    archive_page_url = "https://archive.org/download/#{@content_key}/"
    download_destination_folder = "download/#{@content_key}/"

    downloads = downloads_from_page(archive_page_url, download_destination_folder)
    process_downloads(downloads)
  end

  def downloads_from_page(page_url, destination_folder)
    puts "Scanning: #{page_url}..."
    page_content = Nokogiri::HTML( URI.open(page_url) )
    links = page_content.css('table.directory-listing-table > tbody > tr > td > a').map { |link| link['href'] }

    links.collect do |file_name|
      file_path = "#{destination_folder}#{file_name}"
      if file_name.start_with?('.') || file_name.start_with?('/details/')
        next
      elsif file_name.end_with?('/')
        downloads_from_page("#{page_url}#{file_name}", file_path)
      elsif valid_extension?(file_name)
        file_path = CGI.unescape(file_path)
        next if File.exist?(file_path)

        url = "#{page_url}#{file_name}"
        Download.new(progress_bars: @progress_bars, url: url, path: file_path, logger: @logger)
      end
    end.compact.flatten
  end

  def valid_extension?(file_name)
    return true if @filter_ext_match.nil?

    if @filter_ext_match.none? { |ext_match| file_name.end_with?(ext_match) }
      return false
    end

    if @filter_ext_exclusion&.any? { |ext_exclusion| file_name.end_with?(ext_exclusion) }
      return false
    end

    true
  end

  # Process hash in batches of 10 asynchronously
  def process_downloads(downloads)
    system('clear')
    @progress_bars.start

    pool = Concurrent::ThreadPoolExecutor.new(
      min_threads: 1,
      max_threads: MAX_THREAD_COUNT,
      max_queue: MAX_QUEUE_SIZE * 2,
      fallback_policy: :caller_runs
    )

    # We need to clean up any failed downloads. We should consider either
    # deleting sucessfully downloaded items from list or marking them as done
    downloads.each do |download|
      sleep 10 while pool.queue_length >= MAX_QUEUE_SIZE
      pool.post { download.start }
      # pool.post { download.start_beta }
    end

    pool.shutdown
    pool.wait_for_termination
  end
end

def help_menu_and_exit(exit_code: 0)
  puts <<-"EOHELP"
Internet Archive - Archiver

Usage: #{__FILE__} --content-key <content_key>

OPTIONS
--content-key   : Content Key
--ext-match     : Extension must match given value
--ext-exclusion : Extension must not match given value
--help          : help

  EOHELP
  exit(exit_code)
end

if File.expand_path($PROGRAM_NAME) == File.expand_path(__FILE__)
  options = {}
  parser = OptionParser.new do |opts|
    opts.on('-k', '--content-key content_key') do |content_key|
      options[:content_key] = content_key
    end

    opts.on('-M', '--ext-match filter_ext_match') do |filter_ext_match|
      options[:filter_ext_match] = filter_ext_match
    end

    opts.on('-E', '--ext-exclusion filter_ext_exclusion') do |filter_ext_exclusion|
      options[:filter_ext_exclusion] = filter_ext_exclusion
    end

    opts.on('-h', '--help', 'help menu') do
      help_menu_and_exit
    end
  end

  begin
    parser.parse!
  rescue => ex
    puts ex
    help_menu_and_exit(exit_code: 1)
  end

  Archiver.download(options)
end
