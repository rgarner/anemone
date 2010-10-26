require 'nokogiri'
require 'ostruct'
require 'webrick/cookie'

module Anemone
  class Page

    # The URL of the page
    attr_reader :url
    # The raw HTTP response body of the page
    attr_reader :body
    # Headers of the HTTP response
    attr_reader :headers
    # URL of the page this one redirected to, if any
    attr_reader :redirect_to
    # Exception object, if one was raised during HTTP#fetch_page
    attr_reader :error

    # OpenStruct for user-stored data
    attr_accessor :data
    # Integer response code of the page
    attr_accessor :code
    # Boolean indicating whether or not this page has been visited in PageStore#shortest_paths!
    attr_accessor :visited
    # Depth of this page from the root of the crawl. This is not necessarily the
    # shortest path; use PageStore#shortest_paths! to find that value.
    attr_accessor :depth
    # URL of the page that brought us to this page
    attr_accessor :referer
    # Response time of the request for this page in milliseconds
    attr_accessor :response_time

    #
    # Create a new page
    #
    def initialize(url, params = {})
      @url = url
      @data = OpenStruct.new

      @code = params[:code]
      @headers = params[:headers] || {}
      @headers['content-type'] ||= ['']
      @aliases = Array(params[:aka]).compact
      @referer = params[:referer]
      @depth = params[:depth] || 0
      @redirect_to = to_absolute(params[:redirect_to])
      @response_time = params[:response_time]
      @body = params[:body]
      @error = params[:error]
      @canonical_url = nil
      # Domain synonyms must be an array of URI - core does this for us if necessary,
      # but we don't sanity check Page instances
      @domain_synonyms = params[:domain_synonyms] || []

      @fetched = !params[:code].nil?
    end

    # The canonical URL of the page, if available, or the URL if not
    def key
      self.canonical_url || @url
    end

    # The canonical URL of the page, if requested for the crawl and available
    def canonical_url
      if doc
        canonical_nodes = doc.search('//link[@rel="canonical"]/@href')
        @canonical_url = URI.parse(canonical_nodes.first.content) rescue nil
      end

      @canonical_url
    end

    #
    # Array of distinct A tag HREFs from the page
    #
    def links
      return @links unless @links.nil?
      @links = []
      return @links if !doc

      doc.search("//a[@href]").each do |a|
        u = a['href']
        next if u.nil? or u.empty?
        abs = to_absolute(URI(u)) rescue next
        @links << abs if in_domain?(abs)
      end
      @links.uniq!
      @links
    end

    #
    # Nokogiri document for the HTML body
    #
    def doc
      return @doc if @doc
      @doc = Nokogiri::HTML(@body) if @body && html? rescue nil
    end

    def populate_fields_from_doc
      links
      canonical_url
      nil
    end

    #
    # Delete the Nokogiri document and response body to conserve memory
    #
    def discard_doc!
      populate_fields_from_doc # force parsing of things we need before we trash the document
      @doc = @body = nil
    end

    #
    # Was the page successfully fetched?
    # +true+ if the page was fetched with no error, +false+ otherwise.
    #
    def fetched?
      @fetched
    end

    #
    # Array of cookies received with this page as WEBrick::Cookie objects.
    #
    def cookies
      WEBrick::Cookie.parse_set_cookies(@headers['Set-Cookie']) rescue []
    end

    #
    # The content-type returned by the HTTP request for this page
    #
    def content_type
      headers['content-type'].first
    end

    #
    # Returns +true+ if the page is a HTML document, returns +false+
    # otherwise.
    #
    def html?
      !!(content_type =~ %r{^(text/html|application/xhtml+xml)\b})
    end

    #
    # Returns +true+ if the page is a HTTP redirect, returns +false+
    # otherwise.
    #
    def redirect?
      (300..307).include?(@code)
    end

    #
    # Returns +true+ if the page was not found (returned 404 code),
    # returns +false+ otherwise.
    #
    def not_found?
      404 == @code
    end

    #
    # Converts relative URL *link* into an absolute URL based on the
    # location of the page
    #
    def to_absolute(link)
      return nil if link.nil?

      # remove anchor
      link = URI.encode(link.to_s.gsub(/#[a-zA-Z0-9_-]*$/, ''))

      relative = URI(link)
      absolute = @url.merge(relative)

      absolute.path = '/' if absolute.path.empty?

      return absolute
    end

    #
    # Returns +true+ if *uri* is in the same domain as the page, returns
    # +false+ otherwise
    #
    def in_domain?(uri)
      (uri.host == @url.host) ||
              @domain_synonyms.any? { |synonym| uri.host == synonym.host }
    end

    def marshal_dump
      [@url, @headers, @data, @body, @links, @code, @visited, @depth, @referer, @redirect_to, @response_time, @fetched]
    end

    def marshal_load(ary)
      @url, @headers, @data, @body, @links, @code, @visited, @depth, @referer, @redirect_to, @response_time, @fetched = ary
    end

    def to_hash
      {'url' => @url.to_s,
       'canonical_url' => @canonical_url,
       'headers' => Marshal.dump(@headers),
       'data' => Marshal.dump(@data),
       'body' => @body,
       'links' => links.map(&:to_s),
       'code' => @code,
       'visited' => @visited,
       'depth' => @depth,
       'referer' => @referer.to_s,
       'redirect_to' => @redirect_to.to_s,
       'response_time' => @response_time,
       'fetched' => @fetched}
    end

    def self.from_hash(hash)
      url = hash['url']
      page = self.new(url.nil? ? nil : URI(url))
      {'@headers' => Marshal.load(hash['headers']),
       '@data' => Marshal.load(hash['data']),
       '@canonical_url' => url,
       '@body' => hash['body'],
       '@links' => hash['links'].map { |link| URI(link) },
       '@code' => hash['code'].to_i,
       '@visited' => hash['visited'],
       '@depth' => hash['depth'].to_i,
       '@referer' => hash['referer'],
       '@redirect_to' => URI(hash['redirect_to']),
       '@response_time' => hash['response_time'].to_i,
       '@fetched' => hash['fetched']
      }.each do |var, value|
        page.instance_variable_set(var, value)
      end
      page
    end
  end
end
