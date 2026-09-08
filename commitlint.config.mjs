export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    // Subjects are the issue titles and some run past the default 100.
    'header-max-length': [2, 'always', 120],
    // Subjects name tools like CMake and GCC, so the case rule is off.
    'subject-case': [0],
  },
};
