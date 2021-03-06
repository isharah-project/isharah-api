class GesturesController < ApplicationController
  before_action :authenticate_user!, only: %i[review create index_unreviewed]
  # Check to be reviewed gesture exists
  before_action :find_gesture, only: %i[review]
  # Check inputted word exists before creating gesture
  before_action :find_word, only: %i[create]
  after_action :trim_gesture_video, only: %i[create]
  authorize_resource

  def create
    @gesture = Gesture.new(
      user: current_user, word: @word,
      video: create_params[:video]
    )
    if @gesture.save
      render json: GestureSerializer.new(@gesture).serialized_json,
             status: :ok
    else
      render json: @gesture.errors, status: :unprocessable_entity
    end
  end

  def index_unreviewed
    per_page = params[:per_page] || 5
    page = params[:page] || 1

    render json: PaginatedSerializableService.new(
      records: Gesture.with_attached_video
                      .eager_load(word: :categories)
                      .eager_load(:user)
                      .eager_load(:review)
                      .unreviewed,
      serializer_klass: GestureSerializer,
      serializer_options: {
        include: %i[user word word.categories],
        params: { include_preview: true }
      },
      page: page,
      per_page: per_page
    ).build_hash, status: :ok
  end

  def index_recently_added
    per_page = params[:per_page] || 10
    page = params[:page] || 1

    render json: PaginatedSerializableService.new(
      records: Gesture.with_attached_video
                      .eager_load(word: :categories)
                      .eager_load(:user)
                      .dictionary.order(created_at: :desc),
      serializer_klass: GestureSerializer,
      serializer_options: {
        include: %i[word word.categories],
        params: { include_preview: true }
      },
      page: page,
      per_page: per_page
    ).build_hash, status: :ok
  end

  def review
    # Create review
    @review = Review.new(
      reviewer: current_user,
      gesture: @gesture,
      # Trick to make "True", "true", true all equal true.
      # TODO: move this to helper
      accepted: review_params[:accepted].to_s.casecmp('true').zero?,
      comment: review_params[:comment]
    )
    unless @review.save
      render json: @review.errors, status: :unprocessable_entity
      return
    end

    # Make gesture primary if it's the first gesture for this word
    unless Gesture.where(
      word: @gesture.word,
      primary_dictionary_gesture: true
    ).exists? || !@review.accepted
      @gesture.update!(primary_dictionary_gesture: true)
    end

    render json: ReviewSerializer.new(@review).serialized_json, status: :created
  end

  def find_word
    # TODO: replace this with word creation logic if we decide to.
    @word = Word.find_by(name: create_params[:word])
    return if @word.present?

    render json: ErrorSerializableService.new(
      input_name: 'word', error_string: 'Record not found'
    ).build_hash, status: :not_found
  end

  def find_gesture
    # Look for id in unreviewed gestures
    @gesture = Gesture.unreviewed.find_by(id: review_params[:id])
    return if @gesture.present?

    render json: ErrorSerializableService.new(
      input_name: 'gesture_id',
      error_string: 'Record not found or already reviewed'
    ).build_hash, status: :not_found
  end

  def trim_gesture_video
    start = params[:start]
    finish = params[:finish]
    return if start.blank? || finish.blank? || @gesture.errors.present?

    VideoTrimmerService.new(@gesture.video_path, start, finish).trim
  end

  private

  def create_params
    params.permit(:word, :video, :start, :finish)
  end

  def review_params
    params.permit(:id, :accepted, :comment)
  end
end
