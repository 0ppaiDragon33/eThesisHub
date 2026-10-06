/// The programs a thesis group or a student can belong to.
const kPrograms = ['BSIT', 'BSCS', 'BSIS'];

/// The specializations a student can choose, by program.
///
/// Stored on the student's profile as the full name, and copied onto their
/// thesis as `leaderSpecialization` so the adviser and panel can see it.
/// A program with no list here lets the student leave it blank.
const kSpecializationsByProgram = {
  'BSIT': [
    'Artificial Intelligence',
    'Software Development',
    'Networking',
  ],
};

/// The specializations offered for [program], or none.
List<String> specializationsFor(String? program) =>
    kSpecializationsByProgram[program?.trim().toUpperCase()] ?? const [];
