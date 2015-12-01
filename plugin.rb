
p 'version 31'

require 'sketchup.rb'
require 'net/http'
require 'net/https'
require 'base64'
require 'json'

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

def get_file_base64()
	m = Sketchup.active_model
	begin
		m.save_copy 'delete_me.skp'
	rescue ArgumentError
		m.save 'untitled_' + random_name() + '.skp'
		m.save_copy 'delete_me.skp'
	end
	x = IO.binread('delete_me.skp')
	x = Base64.encode64(x)
	x.gsub!("\n", '')
	return x
end

def render_to_data_url(width)
	v = Sketchup.active_model.active_view
	vw = width
	vh = (vw/(v.vpwidth.to_f/v.vpheight)).round
	v.write_image({
		:filename => 'delete_me.png',
		:width => vw,
		:height => vh,
		:transparent => true})
	x = IO.binread('delete_me.png')
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

def gather_ezhome_data(includeSkpFile)
	h = {}
	if includeSkpFile then
		h['skp'] = get_file_base64()
	end
	h['house_img'] = render_to_data_url(3000)
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

UI.add_context_menu_handler do |context_menu|
	context_menu.add_item("ezez") {
		d = UI::WebDialog.new("ezez", false, "ezez", 600, 600, 0, 0, true)
		d.add_action_callback("view") do |web_dialog, action_name|
			p 'view...'
			web_dialog.execute_script('ezhome_view_callback(' + JSON.generate(gather_ezhome_data(false)) + ')')
		end
		d.add_action_callback("upload") do |web_dialog, action_name|
			p 'upload...'
			web_dialog.execute_script('ezhome_upload_callback(' + JSON.generate(gather_ezhome_data(true)) + ')')
		end
		d.add_action_callback("download") do |web_dialog, action_name|
			p 'download...'
			x = action_name
			x = open(x, { ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE }).read
			randomName = 'untitled_' + random_name() + '.skp'
			File.open(randomName, 'w').write(x)
			Sketchup.open_file(randomName)
			web_dialog.execute_script('ezhome_download_callback()')
		end
		d.add_action_callback("dimensions") do |web_dialog, action_name|
			p 'dimensions...'
			convert_dimensions_to_just_feet
		end

		d.set_url('http://sketchup-plugin-website.ezhome.io/index.html')
		d.show()
	}
end
