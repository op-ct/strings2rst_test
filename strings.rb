require 'json'
require 'fileutils'
require 'csv'
`puppet strings generate --emit-json strings.json`  # TODO: pure-ruby

@module_dir = Dir.pwd

metadata_json = File.join(@module_dir, 'metadata.json')
if File.exists?(metadata_json)
  metadata = JSON.parse File.read(metadata_json)
else
  metadata = {
    'name' => 'forge_org-module_name',
    'author' => 'Author Name Goes Here',
  }
end
strings = JSON.parse File.read( 'strings.json' )

# => ["puppet_classes", "defined_types", "resource_types", "providers", "puppet_functions"
# TODO: puppet_functions

things = {}

# TODO: refactor into class
@forge_org = metadata['name'].split(%r(-|/)).first
@module_name = metadata['name'].split(%r(-|/)).last
@module_author = metadata['author']

def cross_ref_name( name, strings_type )
  "pupmod__#{@forge_org}_#{strings_type}_#{name}"
end


def record_csv(name, strings_type, _csv_data)
  _csv_filename = File.join(@data_source_path,cross_ref_name(name,strings_type).gsub(':','_'))+'.csv'
  FileUtils.mkdir_p(File.dirname(_csv_filename))
  File.open(_csv_filename,'w') do |f|
    _csv_data.each do |row|
      f.puts row.to_csv
    end
  end
  _csv_filename
end

def rst_subtitle(subtitle)
  "\n" + subtitle + "\n" + '-' * subtitle.size + "\n\n"
end

def rst_csv_table(data, _csv_filename, extra_depth=0)
  xxx = ''
  File.dirname(data['file']).split(File::SEPARATOR).size
  _dir_depth = File.dirname(data['file']).split(File::SEPARATOR).size-extra_depth
  _csv_rel_path = "..#{File::SEPARATOR}" * _dir_depth
  _csv_filename = File.join( _csv_rel_path, '_data', File.basename(_csv_filename) )
  xxx += ".. csv-table::" + "\n"
  xxx += "  :header-rows: 1\n"
  xxx += "  :file:   #{_csv_filename}\n\n"
  xxx += "\n"
end
strings_types_map = {
  'puppet_classes' => 'class',
  'defined_types'  => 'defined type',
  'resource_types'  => 'resource type',
  'providers'  => 'provider',
  'puppet_functions'  => 'function',
}

FileUtils.rm_rf 'doc'

@root_doc_source_path = File.join('doc', 'source')
@static_source_path   = File.join(@root_doc_source_path, '_static')
@data_source_path     = File.join(@root_doc_source_path, '_data')
@conf_py_path         = File.join(@root_doc_source_path, 'conf.py')


# write conf.py
# This needs to be written each time in order to embed metadata about the
# proejct into the conf.py
FileUtils.mkdir_p File.dirname(@conf_py_path)
conf_py_content = DATA.read
conf_py_content.gsub!('ZZZ',@module_name)
conf_py_content.gsub!('YYY',@module_author)
File.open(@conf_py_path,'w'){ |f| f.puts conf_py_content }

FileUtils.mkdir_p File.dirname(@static_source_path)
FileUtils.mkdir_p @data_source_path

# write others
strings_types_map.keys.each do |strings_type|

  strings[strings_type].each do |data|
    out_path = File.join(
       'doc',
       'source',
       strings_type,
        data['file']
          .sub(%r{^(manifests|lib.*)/},'')
          .sub(/\.(pp|rb)/, '.rst')
    )
    FileUtils.mkdir_p File.dirname(out_path)

    things[ strings_type ] ||= []
    things[ strings_type ] << { :ref => cross_ref_name(data['name'], strings_type), :path => out_path }
    title = "#{strings_types_map.fetch(strings_type)}: #{data['name']}"

    xxx = ''
    xxx += ".. _#{cross_ref_name(data['name'], strings_type)}:\n\n"

    xxx += title + "\n" + '=' * title.size + "\n\n"
    # TODO: refactor into class
    if data.key? 'inherits'
      target = cross_ref_name(data['inherits'],strings_type)
      xxx += ":Inherits:\n  #{data['inherits']}_\n"
    end
    if data.key? 'type_name'
      target = cross_ref_name(data['type_name'],'resource_types')
      xxx += ":Type:\n  :ref:`#{target}`\n"
    end
    xxx += ":File:\n  #{data['file']}\n"
    xxx += ":Lines:\n  #{data['line']}\n"

    xxx += "\n"
    xxx += ".. contents: :depth: 2 \n"

    xxx += "\n"
    # chop off legacy rdoc
    _rdoc_sections = data['docstring']['text'].split(/^==/)
    xxx += _rdoc_sections.first unless _rdoc_sections.empty?
    xxx += "\n"

    if _rdoc_sections.size > 1
      xxx += "\n\n`NOTE: Further rdoc sections (starting with ``==`` ) were automatically removed`\n\n"
    end

    _csv_parameter_data = []
    # FIXME: this skips parameters without defaults

    extra_depth=0
    if ['puppet_classes', 'defined_types'].include? strings_type
      xxx += rst_subtitle('Parameters')
      _csv_parameter_data << ['Parameter','Types','Default','Description']
      data['docstring'].fetch('tags',[]).select{|x| x['tag_name'] == 'param' }.each do |tags|
        row = [tags['name']]
        row << tags['types'].join(', ')
        row << ".. code-block:: Ruby\n\n    #{data['defaults'].fetch(tags['name'], nil)}"
        row <<  tags['text']
        _csv_parameter_data << row
      end
      _csv_filename = record_csv(data['name'], strings_type, _csv_parameter_data)
      xxx += rst_csv_table(data, _csv_filename, extra_depth)
    elsif ['resource_types'].include? strings_type
      extra_depth=2

      xxx += rst_subtitle('properties')
      _csv_parameter_data << ['Name','Values','Default','Description']
      data['properties'].each do |_data|
        _csv_parameter_data << [
          _data['name'],
          _data['values'].map{|v| ".. code-block:: ruby\n\n    #{v}" }.join("\n"),
          ".. code-block:: ruby\n\n    #{_data['default']}",
          _data['description'],
        ]
      end
      _csv_filename = record_csv(data['name'], strings_type, _csv_parameter_data)
      xxx += rst_csv_table(data, _csv_filename, extra_depth)

      xxx += rst_subtitle('parameters')
      xxx += "`not implemented yet (and probably wouldn't look sensible in table format)`\n"
      xxx += "\n"
      xxx += "\n"
      ###_csv_parameter_data << ['Name', 'Default', 'Description'
      ###data['parameters'].each do |_data|
      ###  _default = ''
      ###  if _d = _data.fetch('default')
      ###    _default = ".. code-block:: Ruby\n\n    #{_data['defaults'].fetch(tags['name'], nil)}"
      ###  _csv_parameter_data << [
      ###    _data['name'],
      ###    _default,
      ###    _data['description'],
      ###  ]
      ###end
      ###_csv_filename = record_csv(data['name'], strings_type, _csv_parameter_data)
      ###xxx += rst_csv_table(data, _csv_filename, extra_depth)


      xxx += rst_subtitle('features')
      xxx += "`not implemented yet`\n"
      xxx += "\n"
      xxx += "\n"
      xxx += rst_subtitle('providers')
      strings['providers'].select{|x| x['type_name'] == data['name'] }.each do |provider|
        target = cross_ref_name(provider['name'],'providers')
        xxx += "* :ref:`#{target}` \n"
      end
      xxx += "`not implemented yet`\n"
      xxx += "\n"
      xxx += "\n"
    elsif ['providers'].include? strings_type
      xxx += rst_subtitle('Confines')
      data['confines'].each do |k,v|
        xxx += "\n"
        xxx += ":#{k}:\n    #{v}\n"
      end

      xxx += rst_subtitle('Defaults')
      data['defaults'].each do |k,v|
        xxx += "\n"
        xxx += ":#{k}:\n    #{v}\n"
      end
      xxx += "\n"

      xxx += rst_subtitle('Commands')
      data['commands'].each do |k,v|
        xxx += "- #{k}\n"
      end
      xxx += "\n"
    else
      require 'pry'; binding.pry
    end


    # => ["name", "file", "line", "inherits", "docstring", "defaults", "source"]
    # TODO: should we do anythingspecial if there is no source?

    if _source  = data.fetch('source',false)
      xxx += rst_subtitle('Source')
      xxx += ".. code-block:: Ruby\n"
      xxx += "  :linenos:\n"
      xxx += "\n"
      xxx += _source.gsub(/^/m, '    ')
      xxx += "\n"
      puts xxx
    end

    xxx += "\n"
    puts
    File.open( out_path, 'w' ){|f| f.puts xxx }
  end
end

# write index.rst
out_path = File.join(@root_doc_source_path, 'index.rst')
FileUtils.mkdir_p File.dirname(out_path)
xxx = ''
title = "module: #{@forge_org}-#{@module_name}"
xxx += title + "\n" + '=' * title.size + "\n\n"
things.each do |title, _things|
  xxx += rst_subtitle( title.split('_').map{|x| x.capitalize }.join(' ') )
  xxx += "\n"
  xxx += ".. toctree:\n"
  xxx += "  :maxdepth: 2\n"
  xxx += "\n"
  _things.each do |thing|
    _path = File.join('doc','source')
    xxx += "*  :ref:`#{thing[:ref]}`\n"
  end
  xxx += "\n"
end

File.open( out_path, 'w' ){|f| f.puts(xxx); puts xxx }


__END__
# -*- coding: utf-8 -*-
#
# ZZZ documentation build configuration file, created by
# sphinx-quickstart on Sun Nov 20 16:59:21 2016.
#
# This file is execfile()d with the current directory set to its
# containing dir.
#
# Note that not all possible configuration values are present in this
# autogenerated file.
#
# All configuration values have a default; values that are commented out
# serve to show the default.

import sys
import os

# If extensions (or modules to document with autodoc) are in another directory,
# add these directories to sys.path here. If the directory is relative to the
# documentation root, use os.path.abspath to make it absolute, like shown here.
#sys.path.insert(0, os.path.abspath('.'))

# -- General configuration ------------------------------------------------

# If your documentation needs a minimal Sphinx version, state it here.
#needs_sphinx = '1.0'

# Add any Sphinx extension module names here, as strings. They can be
# ones.
extensions = []

# Add any paths that contain templates here, relative to this directory.
templates_path = ['_templates']

# The suffix(es) of source filenames.
# You can specify multiple suffix as a list of string:
# source_suffix = ['.rst', '.md']
source_suffix = '.rst'

# The encoding of source files.
#source_encoding = 'utf-8-sig'

# The master toctree document.
master_doc = 'index'

# General information about the project.
project = u'ZZZ'
copyright = u'2016, YYY'
author = u'YYY'

# The version info for the project you're documenting, acts as replacement for
# |version| and |release|, also used in various other places throughout the
# built documents.
#
# The short X.Y version.
version = u'0.1.0'
# The full version, including alpha/beta/rc tags.
release = u'0'

# The language for content autogenerated by Sphinx. Refer to documentation
# for a list of supported languages.
#
# This is also used if you do content translation via gettext catalogs.
# Usually you set "language" from the command line for these cases.
language = 'en'

# There are two options for replacing |today|: either, you set today to some
# non-false value, then it is used:
#today = ''
# Else, today_fmt is used as the format for a strftime call.
#today_fmt = '%B %d, %Y'

# List of patterns, relative to source directory, that match files and
# directories to ignore when looking for source files.
exclude_patterns = []

# The reST default role (used for this markup: `text`) to use for all
# documents.
#default_role = None

# If true, '()' will be appended to :func: etc. cross-reference text.
#add_function_parentheses = True

# If true, the current module name will be prepended to all description
# unit titles (such as .. function::).
#add_module_names = True

# If true, sectionauthor and moduleauthor directives will be shown in the
# output. They are ignored by default.
#show_authors = False

# The name of the Pygments (syntax highlighting) style to use.
pygments_style = 'sphinx'

# A list of ignored prefixes for module index sorting.
#modindex_common_prefix = []

# If true, keep warnings as "system message" paragraphs in the built documents.
#keep_warnings = False

# If true, `todo` and `todoList` produce output, else they produce nothing.
todo_include_todos = False


# -- Options for HTML output ----------------------------------------------

# The theme to use for HTML and HTML Help pages.  See the documentation for
# a list of builtin themes.
html_theme = 'alabaster'

# Theme options are theme-specific and customize the look and feel of a theme
# further.  For a list of options available for each theme, see the
# documentation.
#html_theme_options = {}

# Add any paths that contain custom themes here, relative to this directory.
#html_theme_path = []

# The name for this set of Sphinx documents.  If None, it defaults to
# "<project> v<release> documentation".
#html_title = None

# A shorter title for the navigation bar.  Default is the same as html_title.
#html_short_title = None

# The name of an image file (relative to this directory) to place at the top
# of the sidebar.
#html_logo = None

# The name of an image file (within the static path) to use as favicon of the
# docs.  This file should be a Windows icon file (.ico) being 16x16 or 32x32
# pixels large.
#html_favicon = None

# Add any paths that contain custom static files (such as style sheets) here,
# relative to this directory. They are copied after the builtin static files,
# so a file named "default.css" will overwrite the builtin "default.css".
html_static_path = ['_static']

# Add any extra paths that contain custom files (such as robots.txt or
# .htaccess) here, relative to this directory. These files are copied
# directly to the root of the documentation.
#html_extra_path = []

# If not '', a 'Last updated on:' timestamp is inserted at every page bottom,
# using the given strftime format.
#html_last_updated_fmt = '%b %d, %Y'

# If true, SmartyPants will be used to convert quotes and dashes to
# typographically correct entities.
#html_use_smartypants = True

# Custom sidebar templates, maps document names to template names.
#html_sidebars = {}

# Additional templates that should be rendered to pages, maps page names to
# template names.
#html_additional_pages = {}

# If false, no module index is generated.
#html_domain_indices = True

# If false, no index is generated.
#html_use_index = True

# If true, the index is split into individual pages for each letter.
#html_split_index = False

# If true, links to the reST sources are added to the pages.
#html_show_sourcelink = True

# If true, "Created using Sphinx" is shown in the HTML footer. Default is True.
#html_show_sphinx = True

# If true, "(C) Copyright ..." is shown in the HTML footer. Default is True.
#html_show_copyright = True

# If true, an OpenSearch description file will be output, and all pages will
# contain a <link> tag referring to it.  The value of this option must be the
# base URL from which the finished HTML is served.
#html_use_opensearch = ''

# This is the file name suffix for HTML files (e.g. ".xhtml").
#html_file_suffix = None

# Language to be used for generating the HTML full-text search index.
# Sphinx supports the following languages:
#   'da', 'de', 'en', 'es', 'fi', 'fr', 'hu', 'it', 'ja'
#   'nl', 'no', 'pt', 'ro', 'ru', 'sv', 'tr'
#html_search_language = 'en'

# A dictionary with options for the search language support, empty by default.
# Now only 'ja' uses this config value
#html_search_options = {'type': 'default'}

# The name of a javascript file (relative to the configuration directory) that
# implements a search results scorer. If empty, the default will be used.
#html_search_scorer = 'scorer.js'

# Output file base name for HTML help builder.
htmlhelp_basename = 'ZZZdoc'

# -- Options for LaTeX output ---------------------------------------------

latex_elements = {
# The paper size ('letterpaper' or 'a4paper').
#'papersize': 'letterpaper',

# The font size ('10pt', '11pt' or '12pt').
#'pointsize': '10pt',

# Additional stuff for the LaTeX preamble.
#'preamble': '',

# Latex figure (float) alignment
#'figure_align': 'htbp',
}

# Grouping the document tree into LaTeX files. List of tuples
# (source start file, target name, title,
#  author, documentclass [howto, manual, or own class]).
latex_documents = [
    (master_doc, 'ZZZ.tex', u'ZZZ Documentation',
     u'YYY', 'manual'),
]

# The name of an image file (relative to this directory) to place at the top of
# the title page.
#latex_logo = None

# For "manual" documents, if this is true, then toplevel headings are parts,
# not chapters.
#latex_use_parts = False

# If true, show page references after internal links.
#latex_show_pagerefs = False

# If true, show URL addresses after external links.
#latex_show_urls = False

# Documents to append as an appendix to all manuals.
#latex_appendices = []

# If false, no module index is generated.
#latex_domain_indices = True


# -- Options for manual page output ---------------------------------------

# One entry per manual page. List of tuples
# (source start file, name, description, authors, manual section).
man_pages = [
    (master_doc, 'zzz', u'ZZZ Documentation',
     [author], 1)
]

# If true, show URL addresses after external links.
#man_show_urls = False


# -- Options for Texinfo output -------------------------------------------

# Grouping the document tree into Texinfo files. List of tuples
# (source start file, target name, title, author,
#  dir menu entry, description, category)
texinfo_documents = [
    (master_doc, 'ZZZ', u'ZZZ Documentation',
     author, 'ZZZ', 'One line description of project.',
     'Miscellaneous'),
]

# Documents to append as an appendix to all manuals.
#texinfo_appendices = []

# If false, no module index is generated.
#texinfo_domain_indices = True

# How to display URL addresses: 'footnote', 'no', or 'inline'.
#texinfo_show_urls = 'footnote'

# If true, do not generate a @detailmenu in the "Top" node's menu.
#texinfo_no_detailmenu = False
