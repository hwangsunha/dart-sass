// Copyright 2018 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test_process/test_process.dart';

import 'package:sass/src/util/path.dart';

import '../../utils.dart';

/// Defines test that are shared between the Dart and Node.js CLI test suites.
void sharedTests(Future<TestProcess> runSass(Iterable<String> arguments)) {
  Future<TestProcess> watch(Iterable<String> arguments) =>
      runSass(["--no-source-map", "--watch"]..addAll(arguments));

  group("when started", () {
    test("updates a CSS file whose source was modified", () async {
      await d.file("out.css", "x {y: z}").create();
      await new Future.delayed(new Duration(milliseconds: 10));
      await d.file("test.scss", "a {b: c}").create();

      var sass = await watch(["test.scss:out.css"]);
      await expectLater(sass.stdout, emits('Compiled test.scss to out.css.'));
      await sass.kill();

      await d
          .file("out.css", equalsIgnoringWhitespace("a { b: c; }"))
          .validate();
    });

    test("doesn't update a CSS file that wasn't modified", () async {
      await d.file("test.scss", "a {b: c}").create();
      await d.file("out.css", "x {y: z}").create();

      var sass = await watch(["test.scss:out.css"]);
      expect(sass.stdout, emitsDone);
      await tick;
      await sass.kill();

      await d
          .file("out.css", equalsIgnoringWhitespace("a { b: c; }"))
          .validate();
    });
  });

  group("recompiles a watched file", () {
    test("when it's modified", () async {
      await d.file("test.scss", "a {b: c}").create();

      var sass = await watch(["test.scss:out.css"]);
      await expectLater(sass.stdout, emits('Compiled test.scss to out.css.'));

      await d.file("test.scss", "x {y: z}").create();
      await expectLater(sass.stdout, emits('Compiled test.scss to out.css.'));
      await sass.kill();

      await d
          .file("out.css", equalsIgnoringWhitespace("x { y: z; }"))
          .validate();
    });

    test("when it's modified when watched from a directory", () async {
      await d.dir("dir", [d.file("test.scss", "a {b: c}")]).create();

      var sass = await watch(["dir:out"]);
      await expectLater(
          sass.stdout, emits('Compiled dir/test.scss to dir/test.css.'));

      await d.dir("dir", [d.file("test.scss", "x {y: z}")]).create();
      await expectLater(
          sass.stdout, emits('Compiled dir/test.scss to dir/test.css.'));
      await sass.kill();

      await d.dir("dir", [
        d.file("test.css", equalsIgnoringWhitespace("x { y: z; }"))
      ]).validate();
    });

    test("when its dependency is modified", () async {
      await d.file("_other.scss", "a {b: c}").create();
      await d.file("test.scss", "@import 'other'").create();

      var sass = await watch(["test.scss:out.css"]);
      await expectLater(sass.stdout, emits('Compiled test.scss to out.css.'));

      await d.file("_other.scss", "x {y: z}").create();
      await expectLater(sass.stdout, emits('Compiled test.scss to out.css.'));
      await sass.kill();

      await d
          .file("out.css", equalsIgnoringWhitespace("x { y: z; }"))
          .validate();
    });

    test("when its dependency above its directory is modified", () async {
      await d.file("_other.scss", "a {b: c}").create();
      await d.dir("dir", [d.file("test.scss", "@import '../other'")]).create();

      var sass = await watch(["dir:out"]);
      await expectLater(
          sass.stdout, emits('Compiled dir/test.scss to dir/test.css.'));

      await d.file("_other.scss", "x {y: z}").create();
      await expectLater(
          sass.stdout, emits('Compiled dir/test.scss to dir/test.css.'));
      await sass.kill();

      await d.dir("dir", [
        d.file("test.css", equalsIgnoringWhitespace("x { y: z; }"))
      ]).validate();
    });

    test("when it's deleted and re-added", () async {
      await d.file("test.scss", "a {b: c}").create();

      var sass = await watch(["test.scss:out.css"]);
      await expectLater(sass.stdout, emits('Compiled test.scss to out.css.'));

      new File(p.join(d.sandbox, "test.scss")).deleteSync();
      await expectLater(sass.stdout, emits('Deleted out.css.'));

      await d.file("test.scss", "x {y: z}").create();
      await expectLater(sass.stdout, emits('Compiled test.scss to out.css.'));
      await sass.kill();

      await d
          .file("out.css", equalsIgnoringWhitespace("x { y: z; }"))
          .validate();
    });

    group("when its dependency is deleted", () {
      test("and removes the output", () async {
        await d.file("_other.scss", "a {b: c}").create();
        await d.file("test.scss", "@import 'other'").create();

        var sass = await watch(["test.scss:out.css"]);
        await expectLater(sass.stdout, emits('Compiled test.scss to out.css.'));

        new File(p.join(d.sandbox, "_other.scss")).deleteSync();
        await expectLater(sass.stdout, emits('???'));
        await sass.kill();

        await d.nothing("out.css").validate();
      });

      test("but another is available", () async {
        await d.file("_other.scss", "a {b: c}").create();
        await d.file("test.scss", "@import 'other'").create();
        await d.dir("dir", [d.file("_other.scss", "x {y: z}")]).create();

        var sass = await watch(["-I", "dir", "test.scss:out.css"]);
        await expectLater(sass.stdout, emits('Compiled test.scss to out.css.'));

        new File(p.join(d.sandbox, "_other.scss")).deleteSync();
        await expectLater(sass.stdout, emits('Compiled test.scss to out.css.'));
        await sass.kill();

        await d
            .file("out.css", equalsIgnoringWhitespace("x { y: z; }"))
            .validate();
      });

      test("which resolves a conflict", () async {
        await d.file("_other.scss", "a {b: c}").create();
        await d.file("_other.sass", "x\n  y: z").create();
        await d.file("test.scss", "@import 'other'").create();

        var sass = await watch(["test.scss:out.css"]);
        await expectLater(sass.stdout, emits('???'));

        new File(p.join(d.sandbox, "_other.sass")).deleteSync();
        await expectLater(sass.stdout, emits('Compiled test.scss to out.css.'));
        await sass.kill();

        await d
            .file("out.css", equalsIgnoringWhitespace("a { b: c; }"))
            .validate();
      });
    });

    group("when a dependency is added", () {
      group("that was missing", () {
        test("relative to the file", () async {
          await d.file("test.scss", "@import 'other'").create();

          var sass = await watch(["test.scss:out.css"]);
          await expectLater(sass.stdout, emits('???'));

          await d.file("_other.scss", "a {b: c}").create();
          await expectLater(
              sass.stdout, emits('Compiled test.scss to out.css.'));
          await sass.kill();

          await d
              .file("out.css", equalsIgnoringWhitespace("a { b: c; }"))
              .validate();
        });

        test("relative to the file above its directory", () async {
          await d
              .dir("dir", [d.file("test.scss", "@import '../other'")]).create();

          var sass = await watch(["dir:out"]);
          await expectLater(sass.stdout, emits('???'));

          await d.file("_other.scss", "a {b: c}").create();
          await expectLater(
              sass.stdout, emits('Compiled dir/test.scss to dir/test.css.'));
          await sass.kill();

          await d.dir("dir", [
            d.file("test.css", equalsIgnoringWhitespace("a { b: c; }"))
          ]).validate();
        });

        test("on a load path", () async {
          await d.file("test.scss", "@import 'other'").create();
          await d.dir("dir").create();

          var sass = await watch(["-I", "dir", "test.scss:out.css"]);
          await expectLater(sass.stdout, emits('???'));

          await d.dir("dir", [d.file("_other.scss", "a {b: c}")]).create();
          await expectLater(
              sass.stdout, emits('Compiled test.scss to out.css.'));
          await sass.kill();

          await d
              .file("out.css", equalsIgnoringWhitespace("a { b: c; }"))
              .validate();
        });

        test("on a load path that was created", () async {
          await d.file("test.scss", "@import 'other'").create();

          var sass = await watch(["-I", "dir", "test.scss:out.css"]);
          await expectLater(sass.stdout, emits('???'));

          await d.dir("dir", [d.file("_other.scss", "a {b: c}")]).create();
          await expectLater(
              sass.stdout, emits('Compiled test.scss to out.css.'));
          await sass.kill();

          await d
              .file("out.css", equalsIgnoringWhitespace("a { b: c; }"))
              .validate();
        });
      });

      test("that conflicts with the previous dependency", () async {
        await d.file("_other.scss", "a {b: c}").create();
        await d.file("test.scss", "@import 'other'").create();

        var sass = await watch(["test.scss:out.css"]);
        await expectLater(sass.stdout, emits('Compiled test.scss to out.css.'));

        await d.file("_other.sass", "x\n  y: z").create();
        await expectLater(sass.stdout, emits('???'));
        await sass.kill();

        await d.nothing("out.css").validate();
      });

      group("that overrides the previous dependency", () {
        test("on an import path", () async {
          await d.file("test.scss", "@import 'other'").create();
          await d.dir("dir2", [d.file("_other.scss", "a {b: c}")]).create();
          await d.dir("dir1").create();

          var sass = await watch(["-I", "dir1,dir2", "test.scss:out.css"]);
          await expectLater(
              sass.stdout, emits('Compiled test.scss to out.css.'));

          await d.dir("dir1", [d.file("_other.scss", "x {y: z}")]).create();
          await expectLater(
              sass.stdout, emits('Compiled test.scss to out.css.'));
          await sass.kill();

          await d
              .file("out.css", equalsIgnoringWhitespace("x { y: z; }"))
              .validate();
        });

        test("because it's relative", () async {
          await d.file("test.scss", "@import 'other'").create();
          await d.dir("dir", [d.file("_other.scss", "a {b: c}")]).create();

          var sass = await watch(["-I", "dir", "test.scss:out.css"]);
          await expectLater(
              sass.stdout, emits('Compiled test.scss to out.css.'));

          await d.file("_other.scss", "x {y: z}").create();
          await expectLater(
              sass.stdout, emits('Compiled test.scss to out.css.'));
          await sass.kill();

          await d
              .file("out.css", equalsIgnoringWhitespace("x { y: z; }"))
              .validate();
        });

        test("because it's not an index", () async {
          await d.file("test.scss", "@import 'other'").create();
          await d.dir("other", [d.file("_index.scss", "a {b: c}")]).create();

          var sass = await watch(["test.scss:out.css"]);
          await expectLater(
              sass.stdout, emits('Compiled test.scss to out.css.'));

          await d.file("_other.scss", "x {y: z}").create();
          await expectLater(
              sass.stdout, emits('Compiled test.scss to out.css.'));
          await sass.kill();

          await d
              .file("out.css", equalsIgnoringWhitespace("x { y: z; }"))
              .validate();
        });
      });
    });
  });

  group("doesn't recompile the watched file", () {
    test("when an unrelated file is modified", () async {
      await d.dir("dir", [
        d.file("test1.scss", "a {b: c}"),
        d.file("test2.scss", "a {b: c}")
      ]).create();

      var sass = await watch(["dir:out"]);
      await expectLater(
          sass.stdout,
          emitsInAnyOrder([
            'Compiled dir/test1.scss to dir/test1.css.',
            'Compiled dir/test2.scss to dir/test2.css.'
          ]));

      await d.dir("dir", [d.file("test2.scss", "x {y: z}")]).create();
      await expectLater(
          sass.stdout, emits('Compiled dir/test2.scss to dir/test2.css.'));
      expect(
          sass.stdout, neverEmits('Compiled dir/test1.scss to dir/test1.css.'));
      await tick;
      await sass.kill();
    });

    test("when a potential dependency that's not actually imported is added",
        () async {
      await d.file("test.scss", "@import 'other'").create();
      await d.file("_other.scss", "a {b: c}").create();
      await d.dir("dir").create();

      var sass = await watch(["-I", "dir", "test.scss:out.css"]);
      await expectLater(sass.stdout, emits('Compiled test.scss to out.css.'));
      await d.dir("dir", [d.file("_other.scss", "a {b: c}")]).create();

      expect(sass.stdout, neverEmits('Compiled test.scss to out.css.'));
      await tick;
      await sass.kill();

      await d
          .file("out.css", equalsIgnoringWhitespace("a { b: c; }"))
          .validate();
    });
  });

  group("deletes the CSS", () {
    test("when a file is deleted", () async {
      await d.file("test.scss", "a {b: c}").create();

      var sass = await watch(["test.scss:out.css"]);
      await expectLater(sass.stdout, emits('Compiled test.scss to out.css.'));

      new File(p.join(d.sandbox, "test.scss")).deleteSync();
      await expectLater(sass.stdout, emits('Deleted out.css.'));
      await sass.kill();

      await d.nothing("out.css").validate();
    });

    test("when a file is deleted within a directory", () async {
      await d.dir("dir", [d.file("test.scss", "a {b: c}")]).create();

      var sass = await watch(["dir:out"]);
      await expectLater(
          sass.stdout, emits('Compiled dir/test.scss to out/test.css.'));

      new File(p.join(d.sandbox, "dir", "test.scss")).deleteSync();
      await expectLater(sass.stdout, emits('Deleted dir/test.css.'));
      await sass.kill();

      await d.dir("dir", [d.nothing("out.css")]).validate();
    });
  });

  test("creates a new CSS file when a Sass file is added", () async {
    await d.dir("dir").create();

    var sass = await watch(["dir:out"]);
    await tick;

    await d.dir("dir", [d.file("test.scss", "a {b: c}")]).create();
    await expectLater(
        sass.stdout, emits('Compiled dir/test.scss to out/test.css.'));
    await sass.kill();

    await d.dir("dir", [
      d.file("out.css", equalsIgnoringWhitespace("a { b: c; }"))
    ]).validate();
  });

  test("doesn't create a new CSS file when a partial is added", () async {
    await d.dir("dir").create();

    var sass = await watch(["dir:out"]);
    await tick;

    await d.dir("dir", [d.file("_test.scss", "a {b: c}")]).create();
    expect(sass.stdout, neverEmits('Compiled dir/test.scss to out/test.css.'));
    await tick;
    await sass.kill();

    await d.dir("dir", [
      d.file("out.css", equalsIgnoringWhitespace("a { b: c; }"))
    ]).validate();
  });

  group("doesn't allow", () {
    test("--stdin", () async {
      var sass = await watch(["--stdin", "test.scss"]);
      expect(sass.stdout, emits('--watch is not allowed with --stdin.'));
      await sass.shouldExit(64);
    });

    test("printing to stderr", () async {
      var sass = await watch(["test.scss"]);
      expect(sass.stdout,
          emits('--watch is not allowed when printing to stdout.'));
      await sass.shouldExit(64);
    });
  });
}
