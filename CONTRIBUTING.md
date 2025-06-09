# Contributing to MotionEye Bootc Container

Thank you for your interest in contributing to this project! This document provides guidelines and instructions for contributing.

## Code of Conduct

Please be respectful and considerate of others when contributing to this project.

## How to Contribute

### Reporting Issues

1. Check if the issue has already been reported
2. Use the issue template when creating a new issue
3. Include as much relevant information as possible:
   - OS version
   - Container version
   - Steps to reproduce
   - Expected behavior
   - Actual behavior
   - Relevant logs

### Pull Requests

1. Fork the repository
2. Create a new branch for your feature/fix
3. Make your changes
4. Test your changes thoroughly
5. Update documentation if necessary
6. Submit a pull request

### Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/silver-octo-dollop.git
   cd silver-octo-dollop
   ```

2. Build the container:
   ```bash
   podman build -t motioneye-bootc .
   ```

3. Test your changes:
   ```bash
   podman run -d \
     --name motioneye-test \
     -p 8765:8765 \
     -v /path/to/recordings:/var/lib/motioneye \
     --device=/dev/video0:/dev/video0 \
     motioneye-bootc
   ```

### Commit Guidelines

- Use clear and descriptive commit messages
- Reference issues and pull requests in commit messages
- Follow the conventional commits format:
  - feat: for new features
  - fix: for bug fixes
  - docs: for documentation changes
  - style: for formatting changes
  - refactor: for code refactoring
  - test: for adding tests
  - chore: for maintenance tasks

### Testing

- Test your changes on different x86 devices if possible
- Verify all features work as expected
- Check for any performance impacts
- Ensure backward compatibility

### Documentation

- Update README.md if necessary
- Add comments to complex code
- Document any new environment variables
- Update configuration examples

## Review Process

1. All pull requests will be reviewed
2. CI checks must pass
3. Changes must be tested and documented
4. At least one maintainer must approve

## Questions?

Feel free to open an issue for any questions about contributing. 