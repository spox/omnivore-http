require "http"
require "http/client"

require "omnivore"
require "./omnivore-http/*"

module Omnivore::Http

  @@control : Omnivore::Http::Control = Omnivore::Http::Control.new

  def self.control
    @@control
  end

end
