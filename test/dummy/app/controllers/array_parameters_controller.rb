class ArrayParametersController < ApplicationController
  permitted_params_for :create do
    param :tags, type: :array, item_type: :string, example: [ "tag1", "tag2" ]
    param :items, required: true do
      param :ids, type: :array, item_type: :integer, required: true
      param :names, type: :array, item_type: :string, example: [ "item1", "item2" ]
    end
  end

  def create
    render json: resource_params
  end
end
