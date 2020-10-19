require 'spec_helper'
require 'rack/mock'

describe Twilio::HTTP::Client do
  describe 'new tests' do # FIXME: Remove this
    let(:client) { Twilio::HTTP::Client.new(timeout: timeout) }
    let(:connection) { Faraday::Connection.new }
    let(:response) { double('response', status: 301, body: {}.to_json, headers: {}) }
    let(:host) { 'host' }
    let(:port) { 'port' }
    let(:request_headers) { {} }
    let(:auth) { ['username', 'password'] }
    let(:request_method) { 'GET' }
    let(:url) { 'url' }
    let(:timeout) { nil }


    private def spy_on_connection(adapter: Faraday.default_adapter)
      allow(Faraday).to receive(:new)
        .with(url: "#{host}:#{port}", ssl: { verify: true })
        .and_yield(connection)
        .and_return(connection)

      # TODO: Add tests that check these things
      # allow(connection.options).to receive(:params_encoder).with(Faraday::FlatParamsEncoder)
      # allow(connection).to receive(:request).with(:url_encoded)
      # allow(connection).to receive(:adapter).with(adapter)
      # allow(connection).to receive(:headers=).with(request_headers)
      # allow(connection).to receive(:basic_auth).with(*auth)
    end

    private def expect_request(method: request_method.downcase.to_sym, params: nil, data: nil)
      expect(connection).to receive(method).with(url, method == :get ? params : data).and_return(response)
    end

    describe '#request' do
      it 'uses the flat params encoder' do
        spy_on_connection
        expect_request

        client.request(host, port, request_method, url, nil, nil, request_headers, auth)

        expect(connection.options.params_encoder).to eq(Faraday::FlatParamsEncoder)
      end

      it 'url encodes the request' do
        spy_on_connection
        expect_request

        expect(connection).to receive(:request).with(:url_encoded)

        client.request(host, port, request_method, url, nil, nil, request_headers, auth)
      end

      it 'attaches request headers' do
        spy_on_connection
        expect_request

        expect(connection).to receive(:headers=).with(request_headers)

        client.request(host, port, request_method, url, nil, nil, request_headers, auth)
      end

      it 'uses the configured adapter' do
        spy_on_connection
        expect_request

        expect(connection).to receive(:adapter).with(client.adapter)

        client.request(host, port, request_method, url, nil, nil, request_headers, auth)
      end

      it 'uses basic auth credentials' do
        spy_on_connection
        expect_request

        expect(connection).to receive(:basic_auth).with(*auth)

        client.request(host, port, request_method, url, nil, nil, request_headers, auth)
      end
    end

    describe '#timeout' do
      let(:timeout) { 10 }

      it 'can be configured for the instance' do
        spy_on_connection
        expect_request

        client.request(host, port, request_method, url, nil, nil, request_headers, auth)

        expect(client.timeout).to eq(timeout)
        expect(connection.options.open_timeout).to eq(timeout)
        expect(connection.options.timeout).to eq(timeout)
      end

      it 'can be overriden per request' do
        spy_on_connection
        expect_request

        request_timeout = 20
        client.request(host, port, request_method, url, nil, nil, request_headers, auth, request_timeout)

        expect(client.timeout).to eq(timeout)
        expect(connection.options.open_timeout).to eq(request_timeout)
        expect(connection.options.timeout).to eq(request_timeout)
      end
    end

    describe '#last_response' do
      it 'should return the last response received' do
        spy_on_connection
        expect_request

        client.request(host, port, request_method, url, nil, nil, request_headers, auth)

        expect(client.last_response).to_not be_nil
        expect(client.last_response).to be_a(Twilio::Response)
        expect(client.last_response.status_code).to eq(response.status)
        expect(client.last_response.body).to eq(JSON.parse(response.body))
        expect(client.last_response.headers).to eq(response.headers)
      end

      it 'should be reset between requests' do
        spy_on_connection

        expect_request
        client.request(host, port, request_method, url, nil, nil, request_headers, auth)

        last_response = client.last_response

        expect_request
        client.request(host, port, request_method, url, nil, nil, request_headers, auth)

        expect(client.last_response).to_not be(last_response)
      end

      context 'after a 5XX response' do
        let(:response) { double('response', status: 500, body: {}.to_json, headers: {}) }

        it 'should be still be set' do
          spy_on_connection
          expect_request

          client.request(host, port, request_method, url, nil, nil, request_headers, auth)

          expect(client.last_response.status_code).to eq(response.status)
        end
      end

      context 'after a connection error' do
        it 'should be nil after a connection error' do
          spy_on_connection
          expect(connection).to receive(request_method.downcase.to_sym).and_raise(Faraday::ConnectionFailed, 'BOOM')

          expect { client.request(host, port, request_method, url, nil, nil, request_headers, auth) }.to raise_exception(Twilio::REST::TwilioError)

          expect(client.last_response).to be_nil
        end
      end

      context 'after a 400 response with an empty body' do
        let(:response) { double('response', status: 400, body: nil, headers: {}) }

        it 'should have a custom body' do
          spy_on_connection
          expect_request

          client.request(host, port, request_method, url, nil, nil, request_headers, auth)

          expect(client.last_response.status_code).to eq(response.status)
          expect(client.last_response.body).to eq({ 'message' => 'Bad request', 'code' => 400 })
        end
      end
    end

    describe '#last_request' do
      it 'should return the last request made' do
        spy_on_connection
        expect(connection).to receive(request_method).and_return(response)

        client.request(host,
                       port,
                       request_method,
                       url,
                       { 'param-key' => 'param-value' },
                       { 'data-key' => 'data-value' },
                       { 'header-key' => 'header-value' },
                       auth,
                       timeout)

        expect(client.last_request).to_not be_nil
        expect(client.last_request).to be_a(Twilio::Request)
        expect(client.last_request.host).to eq(host)
        expect(client.last_request.port).to eq(port)
        expect(client.last_request.method).to eq(request_method)
        expect(client.last_request.url).to eq(url)
        expect(client.last_request.params).to eq('param-key' => 'param-value')
        expect(client.last_request.data).to eq('data-key' => 'data-value')
        expect(client.last_request.headers).to eq('header-key' => 'header-value')
        expect(client.last_request.auth).to eq(auth)
        expect(client.last_request.timeout).to eq(timeout)
      end

      it 'should be cleared between requests'
      it 'should still be set after a 5XX response'
      it 'should still be set after a connection error'
    end

    describe '#adapter' do
      it 'is set to Faraday.default_adapter by default'
      it 'can be changed'
    end
  end

  describe 'old tests' do # FIXME: Delete these
    before do
      @client = Twilio::HTTP::Client.new
    end

    it 'should allow setting a global timeout' do
      # checks that timeout is set to defaults if request doesn't override

      @client = Twilio::HTTP::Client.new(timeout: 10)
      @connection = Faraday::Connection.new

      expect(Faraday).to receive(:new).and_yield(@connection).and_return(@connection)
      allow_any_instance_of(Faraday::Connection).to receive(:send).and_return(double('response', status: 301, body: {}, headers: {}))

      @client.request('host', 'port', 'GET', 'url', nil, nil, {}, ['a', 'b'])

      expect(@client.timeout).to eq(10)
      expect(@connection.options.open_timeout).to eq(10)
      expect(@connection.options.timeout).to eq(10)
    end

    it 'should allow overriding timeout per request' do
      # checks that request can override timeouts
      @client = Twilio::HTTP::Client.new(timeout: 10)
      @connection = Faraday::Connection.new

      expect(Faraday).to receive(:new).and_yield(@connection).and_return(@connection)
      allow_any_instance_of(Faraday::Connection).to receive(:send).and_return(double('response', status: 301, body: {}, headers: {}))

      @client.request('host', 'port', 'GET', 'url', nil, nil, {}, ['a', 'b'], 20)

      expect(@client.timeout).to eq(10)
      expect(@connection.options.open_timeout).to eq(20)
      expect(@connection.options.timeout).to eq(20)
    end

    it 'should contain a last response' do
      # checks that last_response works
      expect(Faraday).to receive(:new).and_return(Faraday::Connection.new)
      allow_any_instance_of(Faraday::Connection).to receive(:send).and_return(double('response', status: 301, body: {}, headers: { something: '1' }))

      @client.request('host', 'port', 'GET', 'url', nil, nil, {}, ['a', 'b'])

      expect(@client.last_response).to_not be_nil
      expect(@client.last_response.is_a?(Twilio::Response)).to be(true)
      expect(@client.last_response.status_code).to eq(301)
      expect(@client.last_response.headers).to eq(something: '1')
    end

    it 'should contain a last request' do
      # checks that last_request works
      expect(Faraday).to receive(:new).and_return(Faraday::Connection.new)
      allow_any_instance_of(Faraday::Connection).to receive(:send).and_return(double('response', status: 301, body: {}, headers: {}))

      @client.request('host',
                      'port',
                      'GET',
                      'url',
                      { 'param-key' => 'param-value' },
                      { 'data-key' => 'data-value' },
                      { 'header-key' => 'header-value' },
                      ['a', 'b'],
                      'timeout')

      expect(@client.last_request).to_not be_nil
      expect(@client.last_request.is_a?(Twilio::Request)).to be(true)
      expect(@client.last_request.host).to eq('host')
      expect(@client.last_request.port).to eq('port')
      expect(@client.last_request.method).to eq('GET')
      expect(@client.last_request.url).to eq('url')
      expect(@client.last_request.params).to eq('param-key' => 'param-value')
      expect(@client.last_request.data).to eq('data-key' => 'data-value')
      expect(@client.last_request.headers).to eq('header-key' => 'header-value')
      expect(@client.last_request.auth).to eq(['a', 'b'])
      expect(@client.last_request.timeout).to eq('timeout')
    end

    it 'should contain a last response for 5XX status classes' do
      # checks that last_response works for 5XX statuses
      expect(Faraday).to receive(:new).and_return(Faraday::Connection.new)
      allow_any_instance_of(Faraday::Connection).to receive(:send).and_return(double('response', status: 500, body: {}, headers: {}))

      @client.request('host', 'port', 'GET', 'url', nil, nil, {}, ['a', 'b'])
      expect(@client.last_response).to_not be_nil
      expect(@client.last_request.host).to eq('host')
      expect(@client.last_request.port).to eq('port')
      expect(@client.last_request.method).to eq('GET')
      expect(@client.last_request.url).to eq('url')
      expect(@client.last_request.params).to be_nil
      expect(@client.last_request.data).to be_nil
      expect(@client.last_request.headers).to eq({})
      expect(@client.last_request.auth).to eq(['a', 'b'])
      expect(@client.last_request.timeout).to be_nil
      expect(@client.last_response.is_a?(Twilio::Response)).to be(true)
      expect(@client.last_response.status_code).to eq(500)
    end

    it 'should contain a last_response but no response on a connection error' do
      # should set last_response to nil when last_request was a connection error
      expect(Faraday).to receive(:new).and_return(Faraday::Connection.new)
      allow_any_instance_of(Faraday::Connection).to receive(:send).and_raise(Faraday::ConnectionFailed.new('BOOM'))

      expect { @client.request('host', 'port', 'GET', 'url', nil, nil, {}, ['a', 'b']) }.to raise_exception(Twilio::REST::TwilioError)
      expect(@client.last_response).to be_nil
      expect(@client.last_request).to_not be_nil
      expect(@client.last_request.host).to eq('host')
      expect(@client.last_request.port).to eq('port')
      expect(@client.last_request.method).to eq('GET')
      expect(@client.last_request.url).to eq('url')
      expect(@client.last_request.params).to be_nil
      expect(@client.last_request.data).to be_nil
      expect(@client.last_request.headers).to eq({})
      expect(@client.last_request.auth).to eq(['a', 'b'])
      expect(@client.last_request.timeout).to be_nil
    end

    describe 'last_response' do
      let(:last_response) { Twilio::Response.new(200, 'body') }
    end
    it 'previous last_response should be cleared' do
      expect(Faraday).to receive(:new).and_return(Faraday::Connection.new)
      allow_any_instance_of(Faraday::Connection).to receive(:send).and_raise(Faraday::ConnectionFailed.new('BOOM'))
      expect { @client.request('host', 'port', 'GET', 'url', nil, nil, {}, ['a', 'b']) }.to raise_exception(Twilio::REST::TwilioError)
      expect(@client.last_response).to be_nil
    end
  end
end
