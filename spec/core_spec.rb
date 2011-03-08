require File.dirname(__FILE__) + '/spec_helper'
require_storage_engines 'pstore', 'tokyo_cabinet'

module Anemone
  describe Core do

    before(:each) do
      FakeWeb.clean_registry
      @opts = {}
    end

    shared_examples_for "crawl" do
      it "should crawl all the html pages in a domain by following <a> href's" do
        pages = []
        pages << FakePage.new('0', :links => ['1', '2'])
        pages << FakePage.new('1', :links => ['3'])
        pages << FakePage.new('2')
        pages << FakePage.new('3')

        Anemone.crawl(pages[0].url, @opts).should have(4).pages
      end

      it "should not follow links that leave the original domain" do
        pages = []
        pages << FakePage.new('0', :links => ['1'], :hrefs => 'http://www.other.com/')
        pages << FakePage.new('1')

        core = Anemone.crawl(pages[0].url, @opts)

        core.should have(2).pages
        core.pages.keys.should_not include('http://www.other.com/')
      end

      it "should follow links that leave the original domain when domain synonyms are defined" do
        pages = []
        pages << FakePage.new('0', :links => {'1' => 'http://other.example.com'})
        pages << FakePage.new('1', :domain => 'http://other.example.com')

        core = Anemone.crawl(pages[0].url, @opts.merge({:domain_synonyms => ['http://other.example.com']}))

        # core.should have(2).pages
        core.pages.keys.should include('http://other.example.com/1')
      end

      it "should not follow redirects that leave the original domain" do
        pages = []
        pages << FakePage.new('0', :links => ['1'], :redirect => 'http://www.other.com/')
        pages << FakePage.new('1')

        core = Anemone.crawl(pages[0].url, @opts)

        core.should have(2).pages
        core.pages.keys.should_not include('http://www.other.com/')
      end

      it "should follow redirects that leave the original domain when domain synonyms are defined" do
        pages = []
        pages << FakePage.new('0', :links => {'1' => 'http://other.example.com'}, :redirect => 'http://other.example.com/')
        pages << FakePage.new('1')

        core = Anemone.crawl(pages[0].url, @opts.merge(:domain_synonyms => ['http://other.example.com']))

        core.pages.each {|x| puts x.inspect}
        core.should have(3).pages # including the 301
        core.pages.keys.should include('http://other.example.com/1')
      end

      it "should follow http redirects" do
        pages = []
        pages << FakePage.new('0', :links => ['1'])
        pages << FakePage.new('1', :redirect => '2')
        pages << FakePage.new('2')

        Anemone.crawl(pages[0].url, @opts).should have(3).pages
      end

      it "should follow http redirects but keep quiet about them when told to do so" do
        pages = []
        pages << FakePage.new('0', :links => ['1'])
        pages << FakePage.new('1', :redirect => '2')
        pages << FakePage.new('2')

        Anemone.crawl(pages[0].url, @opts.merge(:silence_redirects => true)).should have(2).pages
      end

      it "should accept multiple starting URLs" do
        pages = []
        pages << FakePage.new('0', :links => ['1'])
        pages << FakePage.new('1')
        pages << FakePage.new('2', :links => ['3'])
        pages << FakePage.new('3')

        Anemone.crawl([pages[0].url, pages[2].url], @opts).should have(4).pages
      end

      it "should include the query string when following links" do
        pages = []
        pages << FakePage.new('0', :links => ['1?foo=1'])
        pages << FakePage.new('1?foo=1')
        pages << FakePage.new('1')

        core = Anemone.crawl(pages[0].url, @opts)

        core.should have(2).pages
        core.pages.keys.should_not include(pages[2].url)
      end

      it "should be able to skip links with query strings" do
        pages = []
        pages << FakePage.new('0', :links => ['1?foo=1', '2'])
        pages << FakePage.new('1?foo=1')
        pages << FakePage.new('2')

        core = Anemone.crawl(pages[0].url, @opts) do |a|
          a.skip_query_strings = true
        end

        core.should have(2).pages
      end

      it "should be able to skip links based on a RegEx" do
        pages = []
        pages << FakePage.new('0', :links => ['1', '2'])
        pages << FakePage.new('1')
        pages << FakePage.new('2')
        pages << FakePage.new('3')

        core = Anemone.crawl(pages[0].url, @opts) do |a|
          a.skip_links_like /1/, /3/
        end

        core.should have(2).pages
        core.pages.keys.should_not include(pages[1].url)
        core.pages.keys.should_not include(pages[3].url)
      end

      it "should be able to call a block on every page" do
        pages = []
        pages << FakePage.new('0', :links => ['1', '2'])
        pages << FakePage.new('1')
        pages << FakePage.new('2')

        count = 0
        Anemone.crawl(pages[0].url, @opts) do |a|
          a.on_every_page { count += 1 }
        end

        count.should == 3
      end

      describe "Canonical URLs" do
        EXAMPLE_CANONICAL = 'http://www.example.com/canonical/0'

        before do
          # In this example both http://example.com/0 and http://example.com/0.1 have the same
          # canonical URL http://www.example.com/canonical/0
          @pages = []
          @root_page = FakePage.new('0', :links => ['0.1'], :canonical_url => EXAMPLE_CANONICAL)
          @pages << @root_page
          @pages << FakePage.new('0.1', :canonical_url => EXAMPLE_CANONICAL)
        end

        describe "When turned on" do
          before do
            @core = Anemone.crawl(@pages[0].url, @opts.merge(:use_canonical_urls => true))
          end

          it "should have stored one page only" do
            @core.should have(1).pages
          end

          it "should have stored the first page's content under the canonical url" do
            @core.pages[EXAMPLE_CANONICAL].url.to_s.should == @root_page.url
          end
        end

        describe "When turned off" do
          before do
            @core = Anemone.crawl(@pages[0].url, @opts.merge(:use_canonical_urls => false))
          end

          it "should have stored two pages" do
            @core.should have(2).pages
          end

          it "should have been keyed by non-canonical URL" do
            @core.pages[@root_page.url].should_not be_nil
          end
        end
      end

      it "should not discard page bodies by default" do
        Anemone.crawl(FakePage.new('0').url, @opts).pages.values.first.doc.should_not be_nil
      end

      it "should optionally discard page bodies to conserve memory" do
        core = Anemone.crawl(FakePage.new('0').url, @opts.merge({:discard_page_bodies => true}))
        core.pages.values.first.doc.should be_nil
      end

      it "should discard these pages *after* focus_crawl is called (http://github.com/chriskite/anemone/issues#issue/5)" do
        Anemone.crawl(FakePage.new('0', :hrefs => 'http://somewhere.else/').url,
                      @opts.merge({:discard_page_bodies => true})) do |a|
          a.focus_crawl do |p|
            p.doc.should_not be_nil
            [] #return an enumerable for focus_crawl to chew
          end
        end
      end

      it "should provide a focus_crawl method to select the links on each page to follow" do
        pages = []
        pages << FakePage.new('0', :links => ['1', '2'])
        pages << FakePage.new('1')
        pages << FakePage.new('2')

        core = Anemone.crawl(pages[0].url, @opts) do |a|
          a.focus_crawl { |p| p.links.reject { |l| l.to_s =~ /1/ } }
        end

        core.should have(2).pages
        core.pages.keys.should_not include(pages[1].url)
      end

      it "should optionally delay between page requests" do
        delay = 0.25

        pages = []
        pages << FakePage.new('0', :links => '1')
        pages << FakePage.new('1')

        start = Time.now
        Anemone.crawl(pages[0].url, @opts.merge({:delay => delay}))
        finish = Time.now

        (finish - start).should satisfy { |t| t > delay * 2 }
      end

      it "should optionally obey the robots exclusion protocol" do
        pages = []
        pages << FakePage.new('0', :links => '1')
        pages << FakePage.new('1')
        pages << FakePage.new('robots.txt',
                              :body => "User-agent: *\nDisallow: /1",
                              :content_type => 'text/plain')

        core = Anemone.crawl(pages[0].url, @opts.merge({:obey_robots_txt => true}))
        urls = core.pages.keys

        urls.should include(pages[0].url)
        urls.should_not include(pages[1].url)
      end

      it "should be able to set cookies to send with HTTP requests" do
        cookies = {:a => '1', :b => '2'}
        core = Anemone.crawl(FakePage.new('0').url) do |anemone|
          anemone.cookies = cookies
        end
        core.opts[:cookies].should == cookies
      end

      it "should freeze the options once the crawl begins" do
        core = Anemone.crawl(FakePage.new('0').url) do |anemone|
          anemone.threads = 4
          anemone.on_every_page do
            lambda { anemone.threads = 2 }.should raise_error
          end
        end
        core.opts[:threads].should == 4
      end

      describe "many pages" do
        before(:each) do
          @pages, size = [], 5

          size.times do |n|
            # register this page with a link to the next page
            link = (n + 1).to_s if n + 1 < size
            @pages << FakePage.new(n.to_s, :links => Array(link))
          end
        end

        it "should track the page depth and referer" do
          core = Anemone.crawl(@pages[0].url, @opts)
          previous_page = nil

          @pages.each_with_index do |page, i|
            page = core.pages[page.url]
            page.should be
            page.depth.should == i

            if previous_page
              page.referer.should == previous_page.url
            else
              page.referer.should be_nil
            end
            previous_page = page
          end
        end

        it "should optionally limit the depth of the crawl" do
          core = Anemone.crawl(@pages[0].url, @opts.merge({:depth_limit => 3}))
          core.should have(4).pages
        end
      end

    end

    describe Hash do
      it_should_behave_like "crawl"

      before(:all) do
        @opts = {}
      end
    end

    if testing? 'pstore'
      describe Storage::PStore do
        it_should_behave_like "crawl"

        before(:each) do
          @test_file = 'test.pstore'
          File.delete(@test_file) if File.exists?(@test_file)
          @opts = {:storage => Storage.PStore(@test_file)}
        end

        after(:all) do
          File.delete(@test_file) if File.exists?(@test_file)
        end
      end
    end

    if testing? 'tokyocabinet'
      describe Storage::TokyoCabinet do
        it_should_behave_like "crawl"

        before(:each) do
          @test_file = 'test.tch'
          File.delete(@test_file) if File.exists?(@test_file)
          @opts = {:storage => @store = Storage.TokyoCabinet(@test_file)}
        end

        after(:each) do
          @store.close
        end

        after(:all) do
          File.delete(@test_file) if File.exists?(@test_file)
        end
      end
    end

    describe "options" do
      it "should accept options for the crawl" do
        core = Anemone.crawl(SPEC_DOMAIN, :verbose => false,
                             :threads => 2,
                             :discard_page_bodies => true,
                             :user_agent => 'test',
                             :obey_robots_txt => true,
                             :depth_limit => 3,
                             :use_canonical_urls => true)

        core.opts[:verbose].should == false
        core.opts[:threads].should == 2
        core.opts[:discard_page_bodies].should == true
        core.opts[:delay].should == 0
        core.opts[:user_agent].should == 'test'
        core.opts[:obey_robots_txt].should == true
        core.opts[:depth_limit].should == 3
        core.opts[:use_canonical_urls].should == true
      end

      it "should accept options via setter methods in the crawl block" do
        core = Anemone.crawl(SPEC_DOMAIN) do |a|
          a.verbose = false
          a.threads = 2
          a.discard_page_bodies = true
          a.user_agent = 'test'
          a.obey_robots_txt = true
          a.depth_limit = 3
          a.use_canonical_urls = true
        end

        core.opts[:verbose].should == false
        core.opts[:threads].should == 2
        core.opts[:discard_page_bodies].should == true
        core.opts[:delay].should == 0
        core.opts[:user_agent].should == 'test'
        core.opts[:obey_robots_txt].should == true
        core.opts[:depth_limit].should == 3
        core.opts[:use_canonical_urls].should == true
      end

      it "should use 1 thread if a delay is requested" do
        Anemone.crawl(SPEC_DOMAIN, :delay => 0.01, :threads => 2).opts[:threads].should == 1
      end
    end

  end
end
