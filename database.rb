require 'sequel'
require 'json'

DB = Sequel.sqlite 'plushies.db'

DB.create_table? :plushies do
  primary_key :id
  String   :name,      unique: true, null: false
  Integer  :size,      null: false
  String   :type,      null: false
  String   :location
  TrueClass :admin?,   null: false
  Text     :owners
  TrueClass :missing?, null: false
  TrueClass :core,     null: false
  DateTime :updated_at
end

unless DB.schema(:plushies).map(&:first).include?(:position)
  DB.alter_table(:plushies) { add_column :position, Integer }
  DB[:plushies].where(position: nil).update(position: Sequel[:id])
end

class Plushie < Sequel::Model(:plushies)
  plugin :timestamps, update: :updated_at, update_on_create: true

  def before_create
    self.position ||= (self.class.max(:position) || 0) + 1
    super
  end

  def before_save
    %i[name type].each do |field|
      v = send(field)
      raise ArgumentError, "#{field} cannot be empty" if v.nil? || v.to_s.strip.empty?
    end
    super
  end

  OWNERS = [:Grubma, :Grubmi, :Mimi, :Alex, :Benni]

  def owners
    JSON.parse(super || "[]")
  end

  def owners=(val)
    raise ArgumentError, "owners must be an Array" unless val.is_a?(Array)

    invalid = val.reject { |v| OWNERS.map(&:to_s).include?(v) }
    raise ArgumentError, "invalid owners: #{invalid.inspect}" unless invalid.empty?

    raise ArgumentError, "duplicate owners are not allowed" if val.uniq.length != val.length

    super(val.to_json)
  end
end