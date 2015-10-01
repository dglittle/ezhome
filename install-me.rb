
# require 'open-uri'
# eval(open('http://dglittle.github.io/ezhome/plugin.rb').read)

p 'version 44'

require 'sketchup.rb'
require 'net/http'
require 'net/https'
require 'base64'
require 'json'

UI.add_context_menu_handler do |context_menu|
	context_menu.add_item("ezhome test plugin 44") {
		p 'hello, I am before'
		require 'open-uri'
		p 'hello, I am after'
		UI.messagebox('Hello World!')
	}
end
