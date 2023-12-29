class Download < ActiveRecord::Base
  DEFAULT_HEADERS = { 'user-agent' => 'curl/7.69.1', 'accept' => '*/*' }.freeze

  belongs_to :archive

  # files = Dir.glob("download/#{content_key}/**/*", File::FNM_DOTMATCH)
  #   .reject { |f| File.directory?(f) || f.end_with?('.DS_Store') }
  #   .collect do |p|
  #     {
  #       path: p.delete_prefix("download/#{content_key}/").delete_suffix('.download').gsub(/\/\./, '/'),
  #       size: File.size(p).to_f / (1000**2),
  #       status: p.end_with?('.download') ? '<b>Downloading</b>' : 'Available'
  #     }
  #   end.sort_by{|f| f[:path]}
  def path
    @path ||= begin
                CGI.unescape(
                  filename.delete_prefix("/download/#{archive.key}/")
                )
              end
  end

  def mb_size
    return nil if size.nil?

    (size.to_f / 1024**2).round(2)
  end

  def refresh_byte_size(url: self.url)
    Async do
      logger.info "SCANNER - URL - #{url}"
      endpoint = Async::HTTP::Endpoint.parse(url)
      client = Async::HTTP::Client.new(endpoint)

      response = client.head(endpoint.path, DEFAULT_HEADERS)
      if response.status == 302
        refresh_byte_size(url: response.headers['location'])
      else
        raise 'Could not determine length of response!' unless response.success?

        unless response.headers['accept-ranges'].include?('bytes')
          raise 'Does not advertise support for accept-ranges: bytes!'
        end

        unless (byte_size = response.body&.length).positive?
          raise 'Could not determine length of response!'
        end

        update!(size: byte_size)
      end
    ensure
      response&.close
    end
  end

  private

  def valid_extension?(filename)
    archive.valid_extension?(filename)
  end
end
