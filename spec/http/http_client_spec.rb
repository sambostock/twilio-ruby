require 'spec_helper'
require 'rack/mock'
require 'pry' # TODO: REMOVE ME

describe Twilio::HTTP::Client do
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
      it 'should be nil' do
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
      expect(connection).to receive(request_method.downcase.to_sym).and_return(response)

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

    it 'should be cleared between requests' do
      spy_on_connection
      expect(connection).to receive(request_method.downcase.to_sym).and_return(response)
      client.request(host, port, request_method, url, nil, nil, request_headers, auth, timeout)

      last_response = client.last_response

      expect(connection).to receive(request_method.downcase.to_sym).and_return(response)
      client.request(host, port, request_method, url, nil, nil, request_headers, auth, timeout)

      expect(client.last_response).not_to be(last_response)
    end

    context 'after a 5XX response' do
      let(:response) { double('response', status: 500, body: {}.to_json, headers: {}) }

      it 'should still be set' do
        spy_on_connection
        expect_request

        client.request(host, port, request_method, url, nil, nil, request_headers, auth)

        expect(client.last_request).not_to be_nil
      end
    end

    context 'after a connection error' do
      it 'should still be set' do
        spy_on_connection
        expect(connection).to receive(request_method.downcase.to_sym).and_raise(Faraday::ConnectionFailed, 'BOOM')

        expect { client.request(host, port, request_method, url, nil, nil, request_headers, auth) }.to raise_exception(Twilio::REST::TwilioError)

        expect(client.last_request).not_to be_nil
      end
    end
  end

  describe '#adapter' do
    it 'is set to Faraday.default_adapter by default' do
      expect(client.adapter).to eq(Faraday.default_adapter)
    end

    it 'can be changed' do
      client.adapter = :test

      expect(client.adapter).to eq(:test)
    end
  end
end
