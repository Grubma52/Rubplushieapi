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
  response.headers['Access-Control-Allow-Origin'] = 'http://localhost:5173'
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

def json_error(status_code, message, key: :error)
  status status_code
  { message: "Error", key => message }.to_json
end

def parse_body
  request.body.rewind
  JSON.parse(request.body.read)
rescue JSON::ParserError
  halt json_error(400, "Invalid JSON", key: :message)
end

# --- GET routes ---
get "/" do
  { message: "This is the plushie api", info: File.read("cheat.txt") }.to_json
end

get "/plushie" do
  { message: "The /plushie endpint exists because Scotty wanted it" }.to_json
end

get "/all" do
  { message: "Ok", plushies: Plushie.all.map(&:values) }.to_json
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
  count = Plushie.where(col => params["value"]).count
  { message: "Ok", column: col, value: params["value"], count: count }.to_json
rescue StandardError => e
  json_error(400, e.message)
end

get "/column/:column" do
  col = validate_column!(params["column"])
  values = Plushie.select(col).all.map { |p| p[col] }
  { message: "Ok", column: col, values: values }.to_json
rescue StandardError => e
  json_error(400, e.message)
end

get "/column/:column/:iden" do
  col = validate_column!(params["column"])
  plushie = find_plushie(params["iden"])
  { message: "Ok", column: col, value: plushie[col] }.to_json
rescue Sequel::NoMatchingRow
  json_error(204, "Plushie not found")
rescue StandardError => e
  json_error(400, e.message)
end

get "/plushie/:iden" do
  plushie = find_plushie(params["iden"])
  { message: "Ok", plushie: plushie.values }.to_json
rescue Sequel::NoMatchingRow
  json_error(204, "Plushie not found")
rescue StandardError => e
  json_error(400, e.message)
end

get "/plushie/:iden/:field" do
  plushie = find_plushie(params["iden"])
  field = params["field"].to_sym
  halt json_error(204, "Field '#{field}' not found") unless plushie.values.key?(field)
  plushie.values[field].to_json
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

delete "/:iden" do
  plushie = find_plushie(params["iden"])
  plushie.delete
  { message: "Ok", deleted: plushie.values }.to_json
rescue Sequel::NoMatchingRow
  json_error(204, "Plushie not found")
rescue StandardError => e
  json_error(400, e.message)
end

put "/:iden" do
  payload = parse_body
  plushie = find_plushie(params["iden"])
  plushie.update(payload)
  { message: "Ok", updated: plushie.reload.values }.to_json
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
  { message: "Ok", updated: plushie.reload.values }.to_json
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
