# frozen_string_literal: true

require 'down'
require 'async'
require 'async/clock'
require 'async/barrier'
require 'async/semaphore'
require 'async/http/endpoint'
require 'async/http/client'
require "down/wget"
require 'securerandom'

class Download
  DEFAULT_HEADERS = { 'user-agent' => 'curl/7.69.1', 'accept' => '*/*' }.freeze
  DEFAULT_PARALLEL_COUNT = 4
  DEFAULT_CHUNK_SIZE = 256 * 1024 # 256 KiB chunks

  def initialize(progress_bars: nil, url:, path:, logger: nil)
    @logger = logger

    @context_id = SecureRandom.hex(10)
    @url = url
    @path = path
    reset_url(@url)
    filename = File.basename(path)
    format = ":percent | #{filename} [:bar] :current/:total MiB :rate MiB/s ETA::eta"
    @progress_bar = progress_bars.register(format, width: 60, clear: true)

    @filename = File.basename(@path)
    @directory = File.dirname(@path)

    FileUtils.mkdir_p(@directory) unless File.directory?(@directory)
    @tmp_path = "#{@directory}/.#{@filename}.download"
  end

  def start
    @progress_bar.update(total: content_length/(1024**2))
    @progress_bar.start

    FileUtils.mkdir_p(@directory) unless File.directory?(@directory)
    @file = File.open(@tmp_path, 'w')
    download_in_chunks
    @file.flush
    @file.close

    # File.rename(@tmp_path, @path)
    `ffmpeg -i #{tmp_path} -c copy #{path}`
    File.delete(tmp_path)
  rescue StandardError => ex
    log(ex.full_message, level: :error)
  ensure
    client&.close
    @progress_bar&.finish
  end

  def start_beta
    directory = File.dirname(@path)
    FileUtils.mkdir_p(directory) unless File.directory?(directory)

    file_size = nil
    progress_proc = proc do |current_size|
      @progress_bar.ratio = current_size.to_f / file_size
    end

    content_length_proc = proc do |total_bytes|
      file_size = total_bytes
      @progress_bar.update(total: file_size/(1024**2))
      @progress_bar.start
    end

    Down::Wget.download(
      @url,
      destination: @path,
      content_length_proc: content_length_proc,
      progress_proc: progress_proc
    )

    @progress_bar.finish
  end

  private

  def reset_url(url)
    remove_instance_variable(:@endpoint) if instance_variable_defined?('@endpoint')
    remove_instance_variable(:@client) if instance_variable_defined?('@client')
    @url = url
  end

  def endpoint
    @endpoint ||= Async::HTTP::Endpoint.parse(@url)
  end

  def client
    @client ||= Async::HTTP::Client.new(endpoint)
  end

  def content_length
    @content_length ||= calculate_content_length
  end

  def calculate_content_length
    Async do
      return @content_length unless @content_length.nil?

      begin
        response = client.head(endpoint.path, DEFAULT_HEADERS)
        if response.status == 302
          reset_url(response.headers['location'])
          @content_length = calculate_content_length
        else
          raise 'Could not determine length of response!' unless response.success?

          unless response.headers['accept-ranges'].include?('bytes')
            raise 'Does not advertise support for accept-ranges: bytes!'
          end

          unless (@content_length = response.body&.length).positive?
            raise 'Could not determine length of response!'
          end
        end
      ensure
        response&.close
      end
    end
    @content_length
  end

  def download_in_chunks
    Async do
      amount = 0
      offset = 0

      offset_mutex ||= Mutex.new
      amount_mutex ||= Mutex.new
      semaphore = Async::Semaphore.new(DEFAULT_PARALLEL_COUNT)
      barrier = Async::Barrier.new(parent: semaphore)

      while offset < content_length do
        barrier.async do
          start_byte = end_byte = 0
          offset_mutex.synchronize do
            start_byte = offset
            end_byte = [offset + DEFAULT_CHUNK_SIZE, content_length].min
            offset += DEFAULT_CHUNK_SIZE
          end

          if start_byte >= content_length
            log("FINISHED DOWNLOADED: #{amount}/#{content_length} - START: #{start_byte} - END: #{end_byte}")
            next
          end

          chunk = download_chunk(start_byte: start_byte, end_byte: end_byte)

          add_amount = @file.pwrite(chunk, start_byte)
          amount_mutex.synchronize { amount += add_amount }
          log("DOWNLOADED: #{amount}/#{content_length} - START: #{start_byte} - END: #{end_byte}")
          @progress_bar.ratio = amount.to_f / content_length
        end
      end
      barrier.wait
    end
  end

  def download_chunk(start_byte:, end_byte:)
    retry_count = 10

    while retry_count.positive?
      begin
        response = client.get(
          endpoint.path,
          [['range', "bytes=#{start_byte}-#{end_byte - 1}"], *DEFAULT_HEADERS ]
        )
        return response.read if response&.success?
      rescue StandardError => ex
        log(ex.full_message)
      end

      log("DOWNLOAD FAILED - START: #{start_byte} / END: #{end_byte} / RETRY_COUNT: #{retry_count}", level: :error)
      log("BAD RESPONSE: #{response.inspect}", level: :error) unless response.nil?
      retry_count -= 1
    end
    raise 'Failed to download chunk'
  end

  def log(message, level: :info)
    @logger.send(level, self) { "[#{@context_id}] #{message}" }
  end
end
