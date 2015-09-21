require 'sketchup.rb'
require 'net/http'
require 'net/https'
require 'base64'
require 'json'

p 'version 15'

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

def main
	h = {}

	v = Sketchup.active_model.active_view
	v.write_image 'testing_xyz.jpg', 300, (300.0/(v.vpwidth.to_f/v.vpheight))
	x = IO.read('testing_xyz.jpg')
	x = Base64.encode64(x)
	x.gsub!("\n", '')
	x = 'data:image/png;base64,' + x
	h['img'] = x

	h['soft (in^2)'] = layer_area_xy('soft')
	h['hard (in^2)'] = layer_area_xy('hard')
	h['pool (in^2)'] = layer_area_xy('pool')
	h['flawn (in^2)'] = layer_area_xy('flawn')
	h['flawn (in)'] = layer_perimeter_xy('flawn')
	h['blawn (in^2)'] = layer_area_xy('blawn')
	h['blawn (in)'] = layer_perimeter_xy('blawn')
	h['building (in^2)'] = layer_area_xy('building')

	https = Net::HTTP.new('ezhome.firebaseio.com', 443)
	https.use_ssl = true
	https.verify_mode = OpenSSL::SSL::VERIFY_NONE
	https.send_request('PATCH', '/hello.json', JSON.generate(h))
	p 'posted'
end

main








# def draw_stairs

	# p layer_area('hard')


	# e = Sketchup.active_model.entities

	# y = []
	# e.each { |e| if e.layer.name == 'soft' and e.is_a?(Sketchup::Face) then y.push(e) end }

	# p y[0].is_a?(Sketchup::Face)
	# p y[1].is_a?(Sketchup::Face)
	# p 'what?'


	# area = 0
	# y.each { |y| area += y.area }
	# y.each { |y| p y.area }
	# f = y[0]
	# f = f.mesh
	# p 'polys: ' + f.polygons.to_s
	# p 'points: ' + f.points.to_s
	# p 'area: ' + area.to_s




# "polys: [[-1, 2, 3], [-2, -1, -4], [-4, 1, 5], [6, -2, 4]]"
# "points: [Point3d(-131.627, 213.877, 0), Point3d(-239.939, 127.189, 0), Point3d(-239.939, 213.877, 0), Point3d(-174.452, 141.565, 0), Point3d(-131.627, 141.565, 0), Point3d(-174.452, 127.189, 0)]"

# "polys: [[-1, 2, 3], [-2, -1, -4], [-4, 1, 5], [6, -2, 4]]"
# "points: [Point3d(-131.627, 314.651, 0), Point3d(-365.852, 127.189, 0), Point3d(-365.852, 314.651, 0), Point3d(-224.236, 158.277, 0), Point3d(-131.627, 158.277, 0), Point3d(-224.236, 127.189, 0)]"


# "points: [Point3d(13.8349, 162.337, 13.2251), Point3d(24.1256, 145.61, -4.87342), Point3d(8.91482, 145.61, 1.52059), Point3d(29.0457, 162.337, 6.83109)]"



	# Sketchup.active_model.active_view.write_image '/Users/greglittle/hellotest.jpg', 300, 300
	# x = IO.read('/Users/greglittle/hellotest.jpg')
	# x = Base64.encode64(x)
	# x.gsub!("\n", '')
	# x = 'data:image/png;base64,' + x

	# https = Net::HTTP.new('ezhome.firebaseio.com', 443)
	# https.use_ssl = true
	# https.verify_mode = OpenSSL::SSL::VERIFY_NONE
	# https.send_request('PATCH', '/.json', '{"img" : "' + x + '"}')
	# p 'posted'

	# req = Net::HTTP::Post.new('/img.json')
	# req.body = '"bloop2"'
	# res = https.request(req)
	# puts "Response #{res.code} #{res.message}: #{res.body}"

	# model = Sketchup.active_model
	# entities = model.entities

	# pt1 = Geom::Point3d.new -10, -10, 0
	# pt2 = Geom::Point3d.new -10, 10, 0
	# pt3 = Geom::Point3d.new 10, 10, 0
	# pt4 = Geom::Point3d.new 10, -10, 0

	# f = entities.add_face pt1, pt2, pt3, pt4
	# f.pushpull 3

	# t = Geom::Transformation.new([0, 0, 0])

	# for step in 1..100
	# 	pt1 = Geom::Point3d.new -10, -10, 0
	# 	pt2 = Geom::Point3d.new -10, 10, 0
	# 	pt3 = Geom::Point3d.new 10, 10, 0
	# 	pt4 = Geom::Point3d.new 10, -10, 0

	# 	randomDir = Geom::Vector3d.new (rand-0.5), (rand-0.5), (rand-0.5)
	# 	randomDir.normalize!
	# 	p randomDir
	# 	r = Geom::Transformation.rotation [0, 0, 0], randomDir, 0.3
	# 	forward = Geom::Transformation.new([23, 0, 0])
	# 	t = t * forward * r

	# 	pt1.transform! t
	# 	pt2.transform! t
	# 	pt3.transform! t
	# 	pt4.transform! t

	# 	f = entities.add_face pt1, pt2, pt3, pt4
	# 	f.pushpull 3
	# end
# end
