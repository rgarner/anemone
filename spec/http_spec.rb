require File.dirname(__FILE__) + '/spec_helper'

module Anemone
  ORIGINAL_URI = 'http://www.original.com/contact/1'
  REDIRECTED_URI = 'https://synonym.original.com/contact/1'
  describe HTTP do

    describe "fetch_page" do
      before(:each) do
        FakeWeb.clean_registry
      end

      it "should still return a Page if an exception occurs during the HTTP connection" do
        http = HTTP.new
        http.should_receive(:refresh_connection).once.and_raise(RuntimeError)
        http.fetch_page(SPEC_DOMAIN).should be_an_instance_of(Page)
      end

      describe "respecting domain synonyms on redirection" do
        before do
          # Domain synonyms are ordinarily coerced to an array of URIs by core.rb.
          # This is a bad/brittle test as it has knowledge of this
          http = HTTP.new(:domain_synonyms => [URI('http://synonym.original.com')])
          FakeWeb.register_uri(:get, ORIGINAL_URI, {:status => [301, "Moved Permanently"], :location => REDIRECTED_URI})
          FakeWeb.register_uri(:get, REDIRECTED_URI, {:status => 200, :body => 'success!'})

          @page = http.fetch_page(ORIGINAL_URI)
        end

        specify { @page.code.should == 200 }
        specify { @page.body.should include('success') }
      end

    end
  end
end
