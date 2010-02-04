use ExtUtils::MakeMaker;
WriteMakefile(
    'NAME'          => 'CPAN-Testers-Data-Uploads-Mailer',
    'VERSION_FROM'  => 'lib/CPAN/Testers/Data/Uploads/Mailer.pm',
    'PREREQ_PM'     => {

      'Email::Simple'       => 0,
      'File::Basename'      => 0,
      'File::Path'          => 0,
      'File::Slurp'         => 0,
      'Getopt::ArgvFile'    => 0,
      'Getopt::Long'        => 0,
      'IO::File'            => 0,
      'Template'            => 0,
      'Time::Piece'         => 0,

    },

    NO_META             => 1,

    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT	=> 'Verify CPAN uploads and mails reports',
       AUTHOR	=> 'Barbie <barbie@cpan.org>') : ()),
);
