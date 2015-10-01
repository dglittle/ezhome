
# require 'open-uri'
# eval(open('http://dglittle.github.io/ezhome/plugin.rb').read)

v = '45'
p 'version ' + v

require 'sketchup.rb'
require 'net/http'
require 'net/https'
require 'base64'
require 'json'

UI.add_context_menu_handler do |context_menu|
	context_menu.add_item("ezhome test plugin " + v) {
		p 'hello, I am before. Version ' + v
		require 'open-uri'
		x = open('http://dglittle.github.io/ezhome/plugin.rb').read
		x = x.to_s
		x = x.length
		p 'read this much: ' + x.to_s
		p 'hello, I am after.'
		UI.messagebox('Hello World ' + v)
	}
end
