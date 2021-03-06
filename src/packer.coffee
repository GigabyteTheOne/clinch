###
This class pack all together with layout

Тут у нас и происходит встройка данных с 
путями и кодом файлов в шаблон, эмулирующий require и export
###

_       = require 'lodash'
async   = require 'async'

clinch_package = require '../package.json'

class Packer
  constructor: (@_bundle_processor_, @_options_={}) ->
    # for debugging 
    @_do_logging_ = if @_options_.log? and @_options_.log is on and console?.log? then yes else no

    @_settings_ = 
      strict : @_options_.strict ? on
      inject : @_options_.inject ? on
      cache_modules: @_options_.cache_modules ? on

    @_clinch_verison_ = clinch_package.version

  ###
  This method create browser package with given configuration
  ###
  buldPackage : (package_config, main_cb) ->

    @_bundle_processor_.buildAll package_config, (err, package_code) =>
      return main_cb err if err
      main_cb null, @_assemblePackage package_code, package_config

  ###
  This method assemble result .js file from bundleset
  ###
  _assemblePackage : (package_code, package_config) ->
    # console.log util.inspect package_code, true, null, true

    # prepare environment
    [ env_header, env_body ] = @_buildEnvironment package_code.environment_list, package_code.members

    # set header
    result = @_getHeader env_header, package_config.strict, package_code.dependencies_tree
    # add sources
    result += @_getSource package_code.source_code
    # add environment body
    result += env_body
    # add bundle export
    result += @_getExportDef package_config, package_code
    # add footer
    result + "\n" + @_getFooter()

  ###
  This method build "environment" - local for package variables
  They immitate node.js internal gobal things (like process.nextTick, f.e.)
  ###
  _buildEnvironment : (names, paths) ->
    # just empty strings if no environment
    unless names.length
      return ['','']

    header  = "/* this is environment vars */\nvar " + names.join(', ') + ';'
    
    body    = _.reduce names, (memo, val) ->
      memo += "#{val} = require(#{paths[val]});\n"
    , ''

    [ header, body ]


  ###
  This method create full clinch header
  ###
  _getHeader : (env_header, strict_settings, dependencies_tree) ->
    """
    // Generated by clinch #{@_clinch_verison_}
    (function() {
      #{@_getStrictLine strict_settings}
      #{env_header}
      #{@_getBoilerplateJS()}
      dependencies = #{JSON.stringify dependencies_tree};
    """

  ###
  This method gather all sources
  ###
  _getSource : (source_obj) ->

    result = "\n  sources = {\n"
    source_index = 0
    for own name, code of source_obj
      result += if source_index++ is 0 then "" else ",\n"
      result += JSON.stringify name
      result += ": function(exports, module, require) {#{code}\n}"
    result += "};\n"

  ###
  This method create export definition part
  ###
  _getExportDef : ({package_name, inject}, package_code) ->

    inject = @_settings_.inject unless inject?
    prefix = @_getMemberPrefix inject

    "/* bundle export */\n" + if package_name?
      """
        #{prefix}#{package_name} = {
          #{@_showBundleMembers package_code, '', ':'}
        };
      """
    else
      @_showBundleMembers package_code, prefix, '='


  ###
  This method will show all bundle members for exports part
  ###
  _showBundleMembers : ({bundle_list, members}, member_prefix, delimiter) ->

    members = for bundle_name in bundle_list
      """
      #{member_prefix}#{bundle_name} #{delimiter} require(#{members[bundle_name]})
      """
    
    members.join ",\n"
    
  ###
  This method return  `use 'strict';` line or empty is strict mode supressed
  ###
  _getStrictLine : (isStrict = @_settings_.strict) ->
    if isStrict then "'use strict';" else ''

  ###
  This method return bundle prefix, will used to supress bundle injection
  ###
  _getMemberPrefix : (isInject) ->
    if isInject then 'this.' else 'var '

  ###
  This is header for our browser package
  ###
  _getBoilerplateJS : () ->
    if @_settings_.cache_modules
      cacheModulesStr1 = "  var modules_cache = [];"
      cacheModulesStr2 = """
          resolved_name = resolved_name || name;
            if (modules_cache[resolved_name]) {
              return modules_cache[resolved_name];
            }
        """ 
      cacheModulesStr3 = "modules_cache[resolved_name] = res;"
    else
      cacheModulesStr1 = cacheModulesStr2 = cacheModulesStr3 = ""

    """    
    var dependencies, name_resolver, require, sources, _this = this;
    #{cacheModulesStr1}

    name_resolver = function(parent, name) {
      if (dependencies[parent] == null) {
        throw Error("no dependencies list for parent |" + parent + "|");
      }
      if (dependencies[parent][name] == null) {
        throw Error("no one module resolved, name - |" + name + "|, parent - |" + parent + "|");
      }
      return dependencies[parent][name];
    };
    require = function(name, parent) {
      var exports, module, module_source, resolved_name, _ref;
      if (!(module_source = sources[name])) {
        resolved_name = name_resolver(parent, name);
        if (!(module_source = sources[resolved_name])) {
          throw Error("can`t find module source code: original_name - |" + name + "|, resolved_name - |" + resolved_name + "|");
        }
      }

      #{cacheModulesStr2}

      module_source.call(_this,exports = {}, module = {}, function(mod_name) {
        return require(mod_name, resolved_name != null ? resolved_name : name);
      });
      var res = (_ref = module.exports) != null ? _ref : exports;

      #{cacheModulesStr3}

      return res;
    };
    """

  ###
  This is footer of code wrapper
  ###
  _getFooter : ->
    """
}).call(this);
    """

module.exports = Packer