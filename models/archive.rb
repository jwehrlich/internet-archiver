require 'uri'
require_relative 'download'

class Archive < ActiveRecord::Base
  has_many :downloads

  after_create do |archive|
    Thread.new do
      create_downloads_from_page_files(
        url: "https://archive.org/download/#{archive.key}/",
      )
      update!(status: 'pending')
    end
  end

  before_destroy do
    Download.where(archive: self).delete_all
  end

  def validate_against_disk
    prev_status = status
    update!(status: 'scanning')
    Thread.new do
      downloads.each do |download|
        download.refresh_byte_size

        path = "download/#{key}/#{download.path}"
        if File.exist?(path) && File.size(path).to_i == download.size.to_i
          download.update!(status: 'downloaded')
        elsif download.status == 'downloading'
          # actively being downloaded, leave it alone
        elsif File.exist?(".#{path}.download")
          download.update!(status: 'downloading')
        else
          # File.delete(path) if File.exist?(path)
          download.update!(status: 'pending')
        end
      end

      if Download.where(archive_id: archive.id).where.not(status: 'downloaded').any?
        archive.update!(status: 'pending')
      else
        archive.update!(status: 'downloaded')
      end
    end
  end

  private

  def allowed_extensions
    @allowed_extensions ||= begin
                              str = "ia.mp4,ai.mp4"
                              str&.split(',')&.collect(&:strip)
                            end
  end

  def excluded_extensions
    @excluded_extensions = begin
                            str = ""
                            str&.split(',')&.collect(&:strip)
                          end
  end

  def create_downloads_from_page_files(url:)
    page_content = Nokogiri::HTML( URI.open(url) )
    rows = page_content.css('table.directory-listing-table > tbody > tr')

    Async do
      rows.each do |row|
        filename = row.css('td > a')&.first['href']

        if filename.start_with?('.') || filename.start_with?('/details/')
          next
        elsif filename.end_with?('/')
          create_downloads_from_page_files(url: "#{url}#{filename}")
        elsif valid_extension?(filename)
          uri = URI::parse(url)
          Download.find_or_create_by(
            archive: self,
            filename: "#{CGI.unescape(uri.path)}#{filename}",
            url: "#{url}#{filename}"
          ).tap do |download|
            download.update!(
              size: row.css('td[3]').text.to_f * 1024**2,
              status: 'pending'
            )
          end
        end
      end
    end
  end

  def refresh_download_details
  end

  def valid_extension?(filename)
    return true if allowed_extensions.nil?

    return false if allowed_extensions.none? { |ext| filename.end_with?(ext) }

    return false if excluded_extensions&.any? { |ext| filename.end_with?(ext) }

    true
  end
end
