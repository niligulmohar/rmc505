Dir.glob('devices/*.rb').each do |filename|
  require filename[0..-4]
end
