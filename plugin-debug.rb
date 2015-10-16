
p 'version 33'

require 'sketchup.rb'
require 'net/http'
require 'net/https'
require 'base64'
require 'json'

UI.add_context_menu_handler do |context_menu|
	context_menu.add_item("ezez-debug") {
		d = UI::WebDialog.new("ezez-debug", false, "ezez-debug", 600, 600, 0, 0, true)
		d.add_action_callback("eval") do |web_dialog, action_name|
			eval(action_name)
		end
		d.set_url('http://dglittle.github.io/ezhome/index-debug.html')
		d.show()
	}
end
