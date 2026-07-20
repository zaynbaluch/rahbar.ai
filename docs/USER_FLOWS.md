# Active User Flows

## First launch

```text
Teacher profile
  -> installed coursework
  -> optional offline AI
  -> home
```

The final step may be skipped. Progress is saved locally so the teacher does not restart from the beginning.

## Open coursework

```text
Home
  -> recently accessed topic
```

or

```text
Home
  -> class
  -> subject
  -> topic
```

The repeated workflow stays within three content-selection clicks.

## Prepare material

```text
Topic
  -> verified lesson or verified MCQ
  -> structured view
  -> save, export, grade, or ask for clarification
```

Custom lesson and MCQ generation appears after the verified options and clearly warns that it may take a while.

## Clarification

The teacher may ask about the current lesson/test or ask a general question. The prompt includes the current material, a small number of retrieved excerpts, and a short recent turn history rather than the full app state.

## OMR grading

```text
MCQ paper
  -> capture/select image
  -> deterministic grading
  -> teacher reviews uncertain or blank answers
  -> save confirmed result
```

Student longitudinal progress and teacher handover are not active MVP workflows.
