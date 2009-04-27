require 'rubygems'
require 'net/http'
require 'timeout'

url = URI.parse("http://localhost:4567")
req = Net::HTTP::Post.new('/')
req.set_form_data({"payload" => File.read('test/payload.txt')}, ';')

res = Net::HTTP.new(url.host, url.port)
res = res.request(req)

case res
when Net::HTTPSuccess
  puts res.body
else
  puts "Failed: #{res.message}"
end
