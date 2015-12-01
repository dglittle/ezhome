
p 'version 34'

$ezhomeFirebaseName = 'ezh-estimator-dev'

require 'sketchup.rb'
require 'net/http'
require 'net/https'
require 'base64'
require 'json'
require 'open-uri'
require 'digest/hmac'
require 'digest/md5'

def convert_dimensions_to_just_feet()
	xx = Sketchup.active_model.entities.find_all { |x| x.is_a?(Sketchup::DimensionLinear) }
	xx.each { |x|
		x.text = (x.start[1].distance(x.end[1]) / 12).round(1).to_s + "'"
		x.has_aligned_text = true
	}
end

def get_layer_faces(layer_name)
	y = []
	Sketchup.active_model.entities.each { |x| if x.layer.name == layer_name and x.is_a?(Sketchup::Face) then y.push(x) end }
	return y
end

def area_xy(a, b, c)
    x = [b[0] - a[0], b[1] - a[1], 0]
    y = [c[0] - a[0], c[1] - a[1], 0]
    # x = [b[0] - a[0], b[1] - a[1], b[2] - a[2]]
    # y = [c[0] - a[0], c[1] - a[1], c[2] - a[2]]

    return 0.5 * Math.sqrt(
        (x[1]*y[2] - x[2]*y[1])**2 +
        (x[2]*y[0] - x[0]*y[2])**2 +
        (x[0]*y[1] - x[1]*y[0])**2)
end

def mesh_area_xy(m)
	a = 0
	m.polygons.each { |p|
		a += area_xy(m.points[p[0].abs - 1], m.points[p[1].abs - 1], m.points[p[2].abs - 1])
	}
	return a
end

def layer_area_xy(layer_name)
	a = 0
	get_layer_faces(layer_name).each { |y| a += mesh_area_xy(y.mesh) }
	return a
end

def perimeter_xy(a, b)
    return Math.sqrt((b[0] - a[0])**2 + (b[1] - a[1])**2)
end

def mesh_perimeter_xy(m)
	a = 0
	m.polygons.each { |p|
		for i in 0..2
			if p[i] > 0
				a += perimeter_xy(m.points[p[i].abs - 1], m.points[p[(i+1)%3].abs - 1])
			end
		end
	}
	return a
end

def layer_perimeter_xy(layer_name)
	a = 0
	get_layer_faces(layer_name).each { |y| a += mesh_perimeter_xy(y.mesh) }
	return a
end

def random_name()
	return (0...8).map { (65 + rand(26)).chr }.join
end

def get_north()
	x = get_layer_faces('north')
	if x.length == 0
		UI.messagebox('no north: please add a box to the "north" layer, and place it north of the origin (it can be hidden to keep it out of view)')
		return 0
	end
	sum = Geom::Vector3d.new(0, 0, 0)
	count = 0
	x.each { |x|
		x.mesh.points.each { |x|
			sum = sum + Geom::Vector3d.new(x[0], x[1], x[2])
			count = count + 1
		}
	}
	x = Geom::Vector3d.new(sum[0]/count, sum[1]/count, sum[2]/count)

	c = Sketchup.active_model.active_view.camera
	eye = Geom::Vector3d.new(c.eye[0], c.eye[1], c.eye[2])
	o = Geom::Vector3d.new(0, 0, 0) - eye
	o = [o.dot(c.xaxis), o.dot(c.yaxis)]
	x = x - eye
	x = [x.dot(c.xaxis), x.dot(c.yaxis)]

	return Math.atan2(x[1] - o[1], x[0] - o[0])
end

def get_file()
	m = Sketchup.active_model
	begin
		m.save_copy 'delete_me.skp'
	rescue ArgumentError
		m.save 'untitled_' + random_name() + '.skp'
		m.save_copy 'delete_me.skp'
	end
	return 'delete_me.skp'
end

def get_file_base64()
	x = IO.binread(get_file())
	x = Base64.encode64(x)
	x.gsub!("\n", '')
	return x
end

def render_to_file(width)
	v = Sketchup.active_model.active_view
	vw = width
	vh = (vw/(v.vpwidth.to_f/v.vpheight)).round
	v.write_image({
		:filename => 'delete_me.png',
		:width => vw,
		:height => vh,
		:transparent => true})

	return 'delete_me.png'
end

def render_to_data_url(width)
	x = IO.binread(render_to_file(width))
	x = Base64.encode64(x)
	x.gsub!("\n", '')
	return 'data:image/png;base64,' + x
end

def calc_scale(width)
	v = Sketchup.active_model.active_view
	vw = width
	vh = (vw/(v.vpwidth.to_f/v.vpheight)).round
	c = v.camera
	tau = 2*Math::PI
	if not c.perspective?
		return c.height / vh
	elsif c.fov_is_height?
		return (Math.tan((c.fov/360*tau)/2) * c.eye.z) / (vh/2)
	else
		return (Math.tan((c.fov/360*tau)/2) * c.eye.z) / (vw/2)
	end
end

def get_sketchup_data()
	h = {}
	h['house_img_ft_per_px'] = calc_scale(3000) / 12
	h['lot_area_sqft'] = layer_area_xy('lot') / 144
	h['soft_area_sqft'] = layer_area_xy('soft') / 144
	h['hard_area_sqft'] = layer_area_xy('hard') / 144
	h['pool_area_sqft'] = layer_area_xy('pool') / 144
	h['front_lawn_area_sqft'] = layer_area_xy('flawn') / 144
	h['front_lawn_perimeter_ft'] = layer_perimeter_xy('flawn') / 12
	h['back_lawn_area_sqft'] = layer_area_xy('blawn') / 144
	h['back_lawn_perimeter_ft'] = layer_perimeter_xy('blawn') / 12
	h['building_area_sqft'] = layer_area_xy('building') / 144
	h['north_radians_counterclockwise_from_right'] = get_north()
	return h
end

def gather_ezhome_data(includeSkpFile)
	h = get_sketchup_data()
	h['house_img'] = render_to_data_url(3000)
	if includeSkpFile then
		h['skp'] = get_file_base64()
	end
	return h
end

def get_from_firebase(path, auth_token)
	uri = URI('https://' + $ezhomeFirebaseName + '.firebaseio.com/' + path + '.json?auth=' + auth_token)
	contents = Net::HTTP.get(uri)
	return JSON.parse(contents)
end

def upload_to_s3(aws_auth, file, mime, ext, slug)
	object_path = slug + '/' + Digest::MD5.file(file).hexdigest + '.' + ext
	object_key = '/sketchup-blueprints/' + object_path
	date = Time.now
	auth_signature = "PUT\n" +
	    "\n" +
	    mime + "\n" +
	    date.rfc822 + "\n" +
	    object_key
	p auth_signature
	signature = Digest::HMAC.base64digest(auth_signature, aws_auth["secret"], Digest::SHA1)
	authorization = "AWS " + aws_auth["key"] + ":" + signature

	uri = URI("http://s3-us-west-2.amazonaws.com" + object_key)

	http = Net::HTTP.new(uri.host, uri.port)

	req = Net::HTTP::Put.new uri
	req.add_field('Content-Type', mime)
	req.add_field('Date', date.rfc822)
	req.add_field('Content-Length', File.size(file))
	req['Authorization'] = authorization
	req.body_stream = File.open(file)

	res = http.request(req)

	return "https://s3-us-west-2.amazonaws.com/sketchup-blueprints/" + object_path
end

def patch_to_firebase(path, auth_token, data)
	uri = URI('https://' + $ezhomeFirebaseName + '.firebaseio.com/' + path + '.json?auth=' + auth_token)

	http = Net::HTTP.new(uri.host, uri.port)
	http.use_ssl = true
	http.verify_mode = OpenSSL::SSL::VERIFY_NONE

	req = Net::HTTP::Patch.new uri
	req.body = JSON.generate(data)

	http.request(req)
end

def generate_random_id
	$alphabets = "abcdefghijklmnopqrstuvwxyz"
	r = Random.new
	result = $alphabets[r.rand($alphabets.length)] + $alphabets[r.rand($alphabets.length)] +
		$alphabets[r.rand($alphabets.length)] + $alphabets[r.rand($alphabets.length)]
	return result
end

def get_price_estimate(front_lawn, back_lawn, front_lawn_perimeter, back_lawn_perimeter, hard_area, soft_area, zip)
	url = "https://vrbvpsscc5.execute-api.us-west-2.amazonaws.com/v1/essentials-estimator?front_lawn=" + front_lawn.to_s + "&back_lawn=" + back_lawn.to_s +
		"&front_lawn_perimeter=" + front_lawn_perimeter.to_s + "&back_lawn_perimeter=" + back_lawn_perimeter.to_s + "&hard_area=" + hard_area.to_s + "&soft_area=" + soft_area.to_s +
		"&zip=" + zip.to_s
	prices = JSON.parse(open(url).read)
	return prices
end

UI.add_context_menu_handler do |context_menu|
	context_menu.add_item("ezez") {
		d = UI::WebDialog.new("ezez", false, "ezez", 600, 700, 0, 0, true)
		d.add_action_callback("view") do |web_dialog, auth_token|
			p 'view...'
			aws = get_from_firebase('aws', auth_token.to_s)
			img_url = upload_to_s3(aws, render_to_file(800), "image/png", "png", "temporary")
			house_data = get_sketchup_data()
			blueprint_data = {}
			blueprint_data["width"] = 600
			blueprint_data["bucket"] = "sketchup-blueprints"
			blueprint_data["name"] = ""
			blueprint_data["address_line_1"] = ""
			blueprint_data["address_line_2"] = ""
			blueprint_data["building_area"] = house_data["building_area_sqft"]
			blueprint_data["hard_area"] = house_data["hard_area_sqft"]
			blueprint_data["soft_area"] = house_data["soft_area_sqft"]
			blueprint_data["pool_area"] = house_data["pool_area_sqft"]
			blueprint_data["front_lawn_area"] = house_data["front_lawn_area_sqft"]
			blueprint_data["back_lawn_area"] = house_data["back_lawn_area_sqft"]
			blueprint_data["front_lawn_perimeter"] = house_data["front_lawn_perimeter_ft"]
			blueprint_data["back_lawn_perimeter"] = house_data["back_lawn_perimeter_ft"]
			blueprint_data["total_lot_area"] = house_data["lot_area_sqft"]
			blueprint_data["house_img_url"] = img_url
			blueprint_data["house_img_ft_per_pixel"] = house_data["house_img_ft_per_px"]
			blueprint_data["north_radians_clockwise_from_pointing_to_the_right"] = -house_data["north_radians_counterclockwise_from_right"]
			blueprint_data["slug"] = "temporary"
			uri = URI("https://vrbvpsscc5.execute-api.us-west-2.amazonaws.com/v1/blueprint_generator")

			http = Net::HTTP.new(uri.host, uri.port)
			http.use_ssl = true
			http.verify_mode = OpenSSL::SSL::VERIFY_NONE

			req = Net::HTTP::Post.new uri
			req.body = JSON.generate(blueprint_data)

			res = JSON.parse(http.request(req).body)
			p res["url"]
			web_dialog.execute_script('ezhome_view_callback("'+res["url"]+'")')
		end
		d.add_action_callback("upload") do |web_dialog, auth_token|
			p 'upload...'
			slug = UI.inputbox(["CAD Slug"], ["Akhtari,455-SAN-MATEO-DR,94025"], "Please enter the CAD slug")
			if slug and slug[0] != "" then
				slug = slug[0]
				aws = get_from_firebase('aws', auth_token.to_s)
				data = get_sketchup_data()
				data["skp_url"] = upload_to_s3(aws, get_file(), "application/vnd.sketchup.skp", "skp", slug)
				data["house_img_url"] = upload_to_s3(aws, render_to_file(3000), "image/png", "png", slug)
				data["modified_at"] = Time.now.to_f * 1000

				patch_to_firebase('home/' + slug, auth_token, data)

				house_data = get_from_firebase("home/" + slug, auth_token)
				prices = get_price_estimate(house_data["front_lawn_area_sqft"], house_data["back_lawn_area_sqft"],
					house_data["front_lawn_perimeter_ft"], house_data["back_lawn_perimeter_ft"], house_data["hard_area_sqft"],
					house_data["soft_area_sqft"], house_data["zip"])

				data = {}
				data["weekly_price"] = prices["weekly"]
				data["biweekly_price"] = prices["biweekly"]

				if !house_data.has_key?("short_url_id") then
					short_url_ids = get_from_firebase('short_url_id', auth_token)
					key = generate_random_id()
					while (short_url_ids.has_key?(key)) do
						key = generate_random_id()
					end
					short_url_update = {}
					short_url_update[key] = true
					patch_to_firebase('short_url_id', auth_token, short_url_update)

					data["short_url_id"] = key
				end

				name = house_data["first_name"] + " " + house_data["last_name"]
				if house_data.has_key?("middle_initial") then
					name = house_data["first_name"] + " " + house_data["middle_initial"] + ". " + house_data["last_name"]
				end

				blueprint_data = {}
				blueprint_data["width"] = 3000
				blueprint_data["bucket"] = "sketchup-blueprints"
				blueprint_data["name"] = name
				blueprint_data["address_line_1"] = house_data["address"]
				blueprint_data["address_line_2"] = house_data["city"] + ". " + house_data["state"] + " " + house_data["zip"]
				blueprint_data["building_area"] = house_data["building_area_sqft"]
				blueprint_data["hard_area"] = house_data["hard_area_sqft"]
				blueprint_data["soft_area"] = house_data["soft_area_sqft"]
				blueprint_data["pool_area"] = house_data["pool_area_sqft"]
				blueprint_data["front_lawn_area"] = house_data["front_lawn_area_sqft"]
				blueprint_data["back_lawn_area"] = house_data["back_lawn_area_sqft"]
				blueprint_data["front_lawn_perimeter"] = house_data["front_lawn_perimeter_ft"]
				blueprint_data["back_lawn_perimeter"] = house_data["back_lawn_perimeter_ft"]
				blueprint_data["total_lot_area"] = house_data["lot_area_sqft"]
				blueprint_data["house_img_url"] = house_data["house_img_url"]
				blueprint_data["house_img_ft_per_pixel"] = house_data["house_img_ft_per_px"]
				blueprint_data["north_radians_clockwise_from_pointing_to_the_right"] = -house_data["north_radians_counterclockwise_from_right"]
				blueprint_data["slug"] = slug

				uri = URI("https://vrbvpsscc5.execute-api.us-west-2.amazonaws.com/v1/blueprint_generator")

				http = Net::HTTP.new(uri.host, uri.port)
				http.use_ssl = true
				http.verify_mode = OpenSSL::SSL::VERIFY_NONE

				req = Net::HTTP::Post.new uri
				req.body = JSON.generate(blueprint_data)

				res = JSON.parse(http.request(req).body)
				data["house_with_legend_img_url"] = res["url"]
				data["modified_at"] = Time.now.to_f * 1000

				patch_to_firebase('home/' + slug, auth_token, data)

				UI.messagebox("Blueprint uploaded!")
			end

			web_dialog.execute_script('ezhome_upload_callback()')
		end
		d.add_action_callback("download") do |web_dialog, auth_token|
			p 'download...'
			slug = UI.inputbox(["CAD Slug"], ["Aaronson,340-ARBOR-RD,94025"], "Please enter the CAD slug")
			if slug and slug[0] != "" then
				house_data = get_from_firebase('home/' + slug[0], auth_token.to_s)
				if house_data.has_key?("skp_url") then
					randomName = 'untitled_' + random_name() + '.skp'
					p house_data["skp_url"]
					File.open(randomName, 'wb') do |file|
							file << open(house_data["skp_url"], { ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE }).read
					end
					Sketchup.open_file(randomName)
					UI.messagebox("Blueprint downloaded!")
				else
					UI.messagebox("Sketchup blueprint not found! Maybe it wasn't uploaded yet?")
				end
			end
			web_dialog.execute_script('ezhome_download_callback()')
		end
		d.add_action_callback("dimensions") do |web_dialog, action_name|
			p 'dimensions...'
			convert_dimensions_to_just_feet
		end

		d.set_url('http://sketchup-plugin-website.ezhome.io/test/index.html')
		d.show()
	}
end
