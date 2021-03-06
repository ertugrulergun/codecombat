RootView = require 'views/core/RootView'
template = require 'templates/courses/teacher-classes-view'
Classroom = require 'models/Classroom'
Classrooms = require 'collections/Classrooms'
Courses = require 'collections/Courses'
Campaign = require 'models/Campaign'
Campaigns = require 'collections/Campaigns'
LevelSessions = require 'collections/LevelSessions'
CourseInstance = require 'models/CourseInstance'
CourseInstances = require 'collections/CourseInstances'
ClassroomSettingsModal = require 'views/courses/ClassroomSettingsModal'
InviteToClassroomModal = require 'views/courses/InviteToClassroomModal'
User = require 'models/User'
utils = require 'core/utils'
helper = require 'lib/coursesHelper'

module.exports = class TeacherClassesView extends RootView
  id: 'teacher-classes-view'
  template: template
  
  events:
    'click .edit-classroom': 'onClickEditClassroom'
    'click .archive-classroom': 'onClickArchiveClassroom'
    'click .unarchive-classroom': 'onClickUnarchiveClassroom'
    'click .add-students-btn': 'onClickAddStudentsButton'
    'click .create-classroom-btn': 'onClickCreateClassroomButton'

  initialize: (options) ->
    super(options)
    @classrooms = new Classrooms()
    @classrooms.fetchMine()
    @supermodel.trackCollection(@classrooms)
    @listenTo @classrooms, 'sync', ->
      for classroom in @classrooms.models
        classroom.sessions = new LevelSessions()
        jqxhrs = classroom.sessions.fetchForAllClassroomMembers(classroom)
        if jqxhrs.length > 0
          @supermodel.trackCollection(classroom.sessions)
    
    @courses = new Courses()
    @courses.fetch()
    @supermodel.trackCollection(@courses)
    
    @courseInstances = new CourseInstances()
    @courseInstances.fetchByOwner(me.id)
    @supermodel.trackCollection(@courseInstances)
    @progressDotTemplate = require 'templates/courses/progress-dot'
    
    # Level Sessions loaded after onLoaded to prevent race condition in calculateDots
  
  afterRender: ->
    super()
    $('.progress-dot').each (i, el) ->
      dot = $(el)
      dot.tooltip({
        html: true
        container: dot
      })
    
  onLoaded: ->
    helper.calculateDots(@classrooms, @courses, @courseInstances)
    super()
    
  onClickEditClassroom: (e) ->
    classroomID = $(e.target).data('classroom-id')
    classroom = @classrooms.get(classroomID)
    modal = new ClassroomSettingsModal({ classroom: classroom })
    @openModalView(modal)
    @listenToOnce modal, 'hide', @render

  onClickCreateClassroomButton: (e) ->
    classroom = new Classroom({ ownerID: me.id })
    modal = new ClassroomSettingsModal({ classroom: classroom })
    @openModalView(modal)
    @listenToOnce modal.classroom, 'sync', ->
      @classrooms.add(modal.classroom)
      @addFreeCourseInstances()
      @render()
    
  onClickAddStudentsButton: (e) ->
    classroomID = $(e.currentTarget).data('classroom-id')
    classroom = @classrooms.get(classroomID)
    modal = new InviteToClassroomModal({ classroom: classroom })
    @openModalView(modal)
    @listenToOnce modal, 'hide', @render
    
  onClickArchiveClassroom: (e) ->
    classroomID = $(e.currentTarget).data('classroom-id')
    classroom = @classrooms.get(classroomID)
    classroom.set('archived', true)
    classroom.save {}, {
      success: =>
        @render()
    }
    
  onClickUnarchiveClassroom: (e) ->
    classroomID = $(e.currentTarget).data('classroom-id')
    classroom = @classrooms.get(classroomID)
    classroom.set('archived', false)
    classroom.save {}, {
      success: =>
        @render()
    }
    
  addFreeCourseInstances: ->
    # so that when students join the classroom, they can automatically get free courses
    # non-free courses are generated when the teacher first adds a student to them
    for classroom in @classrooms.models
      for course in @courses.models
        continue if not course.get('free')
        courseInstance = @courseInstances.findWhere({classroomID: classroom.id, courseID: course.id})
        if not courseInstance
          courseInstance = new CourseInstance({
            classroomID: classroom.id
            courseID: course.id
          })
          # TODO: figure out a better way to get around triggering validation errors for properties
          # that the server will end up filling in, like an empty members array, ownerID
          courseInstance.save(null, {validate: false})
          @courseInstances.add(courseInstance)
          @listenToOnce courseInstance, 'sync', @addFreeCourseInstances
          return
