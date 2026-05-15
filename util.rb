def integer?(str)
  Integer(str)
  true
rescue ArgumentError, TypeError
  false
end