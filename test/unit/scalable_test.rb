require 'test_helper'

class ScalableTest < ActiveSupport::TestCase

  def setup
    User.current_user = Factory(:user)
    @model = Factory :model
    @small_scale = Factory :scale, :title=>"small",:pos=>1
    @medium_scale = Factory :scale, :title=>"medium",:pos=>2
    @large_scale = Factory :scale, :title=>"large",:pos=>3
  end

  test "models have scales" do
    assert @model.respond_to?(:scales)
    assert_equal [],@model.scales
  end

  test "assign scales" do
    @model.scales = [@small_scale]
    @model.save
    scales = Model.find(@model.id).scales
    assert_equal [@small_scale],scales
  end

  test "assign scales using ids" do
    @model.scales = [@small_scale.id]
    @model.save
    scales = Model.find(@model.id).scales
    assert_equal [@small_scale],scales

    #skip invalid id's and handle string id's
    model2=Factory :model
    model2.scales = ["","9999",@small_scale.id.to_s]
    model2.save
    scales = Model.find(model2.id).scales
    assert_equal [@small_scale],scales
  end

  test "updating scales correctly resolves differences" do
    @model.scales = [@small_scale.id]
    @model.save
    assert_no_difference("Annotation.count") do
      @model.scales = [@medium_scale.id]
    end
    @model.save
    assert_equal [@medium_scale],@model.scales
    assert_difference("Annotation.count",1) do
      @model.scales = [@medium_scale.id,@large_scale.id]
    end
    @model.save
    assert_equal [@medium_scale,@large_scale],@model.scales
    assert_difference("Annotation.count",-2) do
      @model.scales = []
    end
    @model.save
    assert_equal [],@model.scales
  end

  test "retrieved scales are ordered" do
    @model.scales = [@large_scale,@small_scale,@medium_scale]
    @model.save
    scales = Model.find(@model.id).scales
    assert_equal [@small_scale,@medium_scale,@large_scale],scales
  end

end