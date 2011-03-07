require 'anemone/http'

module Anemone
  #
  # A Tentacle runs on its own thread and is a +Page+ producer to
  # +core.run+'s consumer
  #
  class Tentacle

    #
    # Create a new Tentacle
    #
    def initialize(link_queue, page_queue, pages, opts = {})
      @link_queue = link_queue
      @page_queue = page_queue
      @pages = pages
      @http = Anemone::HTTP.new(opts)
      @opts = opts
    end

    #
    # Gets links from @link_queue, and returns the fetched
    # Page objects into @page_queue
    #
    def run
      loop do
        link, referer, depth = @link_queue.deq

        break if link == :END

        next if @pages.has_page? link

        @http.fetch_pages(link, referer, depth).each { |page| @page_queue << page }

        delay
      end
    end

    private

    def delay
      sleep @opts[:delay] if @opts[:delay] > 0
    end

  end
end
