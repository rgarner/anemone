begin
  require 'fakeweb'
rescue LoadError
  warn "You need the 'fakeweb' gem installed to test Anemone"
  exit
end

FakeWeb.allow_net_connect = false

module Anemone
  SPEC_DOMAIN = "http://www.example.com/"

  class FakePage
    attr_accessor :links
    attr_accessor :hrefs
    attr_accessor :body

    def initialize(name = '', options = {})
      @name = name
      @links = [options[:links]].flatten if options.has_key?(:links)
      @hrefs = [options[:hrefs]].flatten if options.has_key?(:hrefs)
      @redirect = options[:redirect] if options.has_key?(:redirect)
      @content_type = options[:content_type] || "text/html"
      @body = options[:body]
      @canonical_url = options[:canonical_url]

      create_body unless @body
      add_to_fakeweb
    end

    def url
      SPEC_DOMAIN + @name
    end

    private

    def create_body
      @body = "<html>"
      @body += "<head><link rel=\"canonical\" href=\"#{@canonical_url}\" /></head>" if @canonical_url
      @body += "<body>"
      @links.each{|l| @body += "<a href=\"#{SPEC_DOMAIN}#{l}\"></a>"} if @links
      @hrefs.each{|h| @body += "<a href=\"#{h}\"></a>"} if @hrefs
      @body += "</body></html>"
    end

    def add_to_fakeweb
      options = {:body => @body, :content_type => @content_type, :status => [200, "OK"]}

      if @redirect
        options[:status] = [301, "Permanently Moved"]

        # only prepend SPEC_DOMAIN if a relative url (without an http scheme) was specified
        redirect_url = (@redirect =~ /http/) ? @redirect : SPEC_DOMAIN + @redirect
        options[:location] = redirect_url

        # register the page this one redirects to
        FakeWeb.register_uri(:get, redirect_url, {:body => '',
                                                  :content_type => @content_type,
                                                  :status => [200, "OK"]})
      end

      FakeWeb.register_uri(:get, self.url, options)
    end
  end
end

#default root
Anemone::FakePage.new
