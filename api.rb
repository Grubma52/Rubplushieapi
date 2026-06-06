require "sinatra"
require_relative "database"
require_relative "util"

# This is ok, it is not directly public
set :host_authorization, allow_if: ->(env) { true }

configure do
  set :show_exceptions, false
end

before do
  content_type :json

  allowed_origins = [
    'http://10.0.0.34:5173',
    'https://grubma.grubmi.com',
    'https://localhost:5173'
  ]

  origin = request.env['HTTP_ORIGIN']

  if allowed_origins.include?(origin)
    response.headers['Access-Control-Allow-Origin'] = origin
  end

  response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
  response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
end

options '*' do
  200
end

not_found do
  status 404

  {
    message: "Bad URL",
    error: "The requested url does not exist..."
  }.to_json
end

error do
  status 500

  e = env['sinatra.error']

  {
    message: "Oops, this error somehow slipped through the system",
    error: e.message
  }.to_json
end

# --- Helpers ---

VALID_COLUMNS = Plushie.columns.map(&:to_s).freeze

def find_plushie(iden)
  if integer?(iden)
    Plushie.first!(id: iden.to_i)
  else
    Plushie.first!(name: iden)
  end
end

def validate_column!(col)
  halt json_error(400, "Invalid column '#{col}'") unless VALID_COLUMNS.include?(col)
  col.to_sym
end

def json_error(status_code, message)
  status status_code
  { message: "Error", error: message }.to_json
end

def plushie_to_hash(p)
  p.values.merge(owners: p.owners)
end

def parse_body
  JSON.parse(request.body.read)
rescue JSON::ParserError
  halt json_error(400, "Invalid JSON")
end

# --- GET routes ---
get "/" do
  { message: "This is the plushie api", info: File.read("cheat.txt") }.to_json
end

get "/plushie" do
  { message: "The /plushie endpint exists because Scotty wanted it" }.to_json
end

get "/all" do
  { message: "Ok", plushies: Plushie.order(:position, :id).all.map { |p| plushie_to_hash(p) } }.to_json
rescue StandardError => e
  json_error(400, e.message)
end

get "/count" do
  { message: "Ok", count: Plushie.count }.to_json
rescue StandardError => e
  json_error(400, e.message)
end

get "/last_updated" do
  last = Plushie.max(:updated_at)
  halt json_error(204, "No plushies in table") if last.nil?
  { message: "Ok", last_updated: last }.to_json
rescue StandardError => e
  json_error(400, e.message)
end

# More specific /column/count route must come before /column/:column/:iden
get "/column/count/:column/:value" do
  col = validate_column!(params["column"])
  raw = params["value"]
  schema = Plushie.db_schema[col]
  val = case schema[:type]
        when :boolean then raw == "1"
        when :integer then raw.to_i
        else raw
        end
  count = if col == :owners
    Plushie.where(Sequel.lit("owners LIKE ?", "%\"#{val}\"%")).count
  else
    Plushie.where(col => val).count
  end
  { message: "Ok", column: col, value: val, count: count }.to_json
rescue StandardError => e
  json_error(400, e.message)
end

get "/column/:column" do
  col = validate_column!(params["column"])
  values = Plushie.select(col).all.map { |p| p.send(col) }
  { message: "Ok", column: col, values: values }.to_json
rescue StandardError => e
  json_error(400, e.message)
end

get "/column/:column/:iden" do
  col = validate_column!(params["column"])
  plushie = find_plushie(params["iden"])
  { message: "Ok", column: col, value: plushie.send(col) }.to_json
rescue Sequel::NoMatchingRow
  json_error(204, "Plushie not found")
rescue StandardError => e
  json_error(400, e.message)
end

get "/plushie/:iden" do
  plushie = find_plushie(params["iden"])
  { message: "Ok", plushie: plushie_to_hash(plushie) }.to_json
rescue Sequel::NoMatchingRow
  json_error(204, "Plushie not found")
rescue StandardError => e
  json_error(400, e.message)
end

get "/plushie/:iden/:field" do
  plushie = find_plushie(params["iden"])
  field = params["field"].to_sym
  halt json_error(204, "Field '#{field}' not found") unless plushie.values.key?(field)
  plushie.send(field).to_json
rescue Sequel::NoMatchingRow
  json_error(204, "Plushie not found")
rescue StandardError => e
  json_error(400, e.message)
end

get '/plushies.db' do
  begin
    content_type 'application/octet-stream'

    File.binread './plushies.db'
  rescue StandardError => e
    json_error(400, e.message)
  end
end

# --- DELETE / PUT / POST ---

put "/reorder/r/r" do
  data = parse_body
  order = data["order"]
  halt json_error(400, "order must be an array") unless order.is_a?(Array)

  DB.transaction do
    order.each_with_index do |id, idx|
      plushie = find_plushie(id)
      plushie.update(position: idx + 1)
    end
  end
  { message: "Ok", reordered: true }.to_json
rescue Sequel::NoMatchingRow
  json_error(204, "Plushie not found")
rescue StandardError => e
  json_error(400, e.message)
end

delete "/:iden" do
  plushie = find_plushie(params["iden"])
  plushie.delete
  { message: "Ok", deleted: plushie_to_hash(plushie) }.to_json
rescue Sequel::NoMatchingRow
  json_error(204, "Plushie not found")
rescue StandardError => e
  json_error(400, e.message)
end

put "/:iden" do
  payload = parse_body
  plushie = find_plushie(params["iden"])
  plushie.update(payload)
  { message: "Ok", updated: plushie_to_hash(plushie.reload) }.to_json
rescue Sequel::NoMatchingRow
  json_error(204, "Plushie not found")
rescue StandardError => e
  json_error(400, e.message)
end

put "/:iden/:field" do
  payload = parse_body
  plushie = find_plushie(params["iden"])
  field = params["field"].to_sym
  halt json_error(400, "Field '#{field}' is not a valid column") unless Plushie.columns.include?(field)
  plushie.update(field => payload["value"])
  { message: "Ok", updated: plushie_to_hash(plushie.reload) }.to_json
rescue Sequel::NoMatchingRow
  json_error(204, "Plushie not found")
rescue StandardError => e
  json_error(400, e.message)
end

post "/" do
  payload = parse_body
  Plushie.create(payload)
  { message: "Ok", added: payload }.to_json
rescue StandardError => e
  json_error(400, e.message)
end
