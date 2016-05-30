#!/usr/bin/ruby

require 'json'
require 'logger'
require 'erb'
require 'open-uri'
require 'yaml'
require 'ostruct'
require 'mqtt'

$stdout.sync = true

$url_base = 'https://iot.seeed.cc/v1/node/<%=cmd%>?access_token=<%=access_token%>'

$mqtt_conf = OpenStruct.new(YAML.load_file(File.dirname($0) + '/mqtt_config.yaml'))

$log = Logger.new(STDOUT)
$log.level = Logger::DEBUG

$wio_conf = YAML.load_file(File.dirname($0) + '/wio_config.yaml')

def send_mqtt(mqtt, topic, send_data) 
  json = JSON.generate(send_data)
  $log.debug json
  mqtt.publish(topic, json)
end

def wio2mqtt_inner(mqtt, item, cmd, src_key)
  access_token = item['access_token']

  url = ERB.new($url_base).result(binding)
  $log.debug url

  json = JSON.parse(open(url).read)
  $log.debug json

  send_data = {}
  send_data[item['dst_key']] = json[src_key]
  send_mqtt(mqtt, item['dst_topic'], send_data)
end

def wio2mqtt_dht11_temperature(mqtt, item)
  $log.debug("wio2mqtt_dht11_temperature() : item=#{item}")

  cmd = 'GroveTempHumD0/temperature'
  src_key = 'celsius_degree'

  wio2mqtt_inner(mqtt, item, cmd, src_key)
end

def wio2mqtt_dht11_humidity(mqtt, item)
  $log.debug("wio2mqtt_dht11_humidity() : item=#{item}")

  cmd = 'GroveTempHumD0/humidity'
  src_key = 'humidity'

  wio2mqtt_inner(mqtt, item, cmd, src_key)
end

def wio2mqtt_analog_in(mqtt, item)
  $log.debug("wio2mqtt_analog_in() : item=#{item}")

  cmd = 'GenericAInA0/analog'
  src_key = 'analog'

  wio2mqtt_inner(mqtt, item, cmd, src_key)
end

def wio2mqtt(mqtt, item)
  # for item check...
  if item.nil? || !item.kind_of?(Hash)
    $log.error("invalid item...item=#{item}")
    return false
  end
  ["access_token", "src_type", "dst_topic", "dst_key"].each do |k|
    if !item.key?(k)
      $log.error("item has no key...key=#{k}")
      return false
    end
  end

  case item["src_type"]
    when "dht11_temperature" then
      wio2mqtt_dht11_temperature(mqtt, item)
    when "dht11_humidity" then
      wio2mqtt_dht11_humidity(mqtt, item)
    when "analog_in" then
      wio2mqtt_analog_in(mqtt, item)
    else
      $log.error("invalid item.src_type...src_type=#{item["src_type"]}")
    end
end

def main
  conn_opts = {
    remote_host: $mqtt_conf.mqtt_host,
    remote_port: $mqtt_conf.mqtt_port,
    username:    $mqtt_conf.mqtt_username,
    password:    $mqtt_conf.mqtt_password,
  }

  $log.info "connecting..."
  MQTT::Client.connect(conn_opts) do |c|
    $log.info "connected"

    loop do
      $wio_conf.each do |item|
        wio2mqtt(c, item)
      end
      sleep 10
    end
  end
end

loop do 
  begin
    main
  rescue => e
    $log.error e
    sleep 5
  end
end
