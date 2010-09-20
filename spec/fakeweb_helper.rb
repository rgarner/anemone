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
      @links = [options[:links]].to_a.flatten if options.has_key?(:links)
      @hrefs = [options[:hrefs]].flatten if options.has_key?(:hrefs)
      @redirect = options[:redirect] if options.has_key?(:redirect)
      @content_type = options[:content_type] || "text/html"
      @body = options[:body]
      @domain = options[:domain] || SPEC_DOMAIN

      create_body unless @body
      add_to_fakeweb
    end

    def url
      @domain + @name
    end

    private

    def create_body
      @body = "<html><body>"
      @links.each do |l|
        @body += "<a href=\"#{@domain}#{l}\"></a>" if l.is_a? String
        if l.is_a? Hash
          l.each_pair { |name, domain| @body += "<a href=\"#{File.join(domain, name)}\"></a>" }
        end
      end if @links
      @hrefs.each { |h| @body += "<a href=\"#{h}\"></a>" } if @hrefs
      @body += "</body></html>"
    end

    def add_to_fakeweb
      options = {:body => @body, :content_type => @content_type, :status => [200, "OK"]}

      if @redirect
        options[:status] = [301, "Permanently Moved"]

        # only prepend SPEC_DOMAIN if a relative url (without an http scheme) was specified
        redirect_url = (@redirect =~ /http/) ? @redirect : @domain + @redirect
        options[:location] = redirect_url

        # register the page this one redirects to
        FakeWeb.register_uri(:get, redirect_url, {:body => '',
                                                  :content_type => @content_type,
                                                  :status => [200, "OK"]})
      end

      FakeWeb.register_uri(:get, @domain + @name, options)
    end
  end
end

#default root
Anemone::FakePage.new
