use ExtUtils::MakeMaker;

WriteMakefile(
    dist	 => {
	             PREOP	=> './build && pod2text bin/staticperl | tee README >$(DISTVNAME)/README; chmod -R u=rwX,go=rX . ;',
	             COMPRESS	=> 'gzip -9v',
	             SUFFIX	=> '.gz',
	            },
    NAME         => "App::Staticperl",
    VERSION_FROM => "bin/staticperl",
    EXE_FILES    => ["bin/staticperl"],
    PM           => {},
    MAN3PODS     => {},
);

